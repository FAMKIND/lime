//! The display order of a conversation (`docs/api-v2.md` section 5): causal, with ties broken by
//! HLC, then by op id. The server's cursor says nothing about it; it is the same on every device
//! and the same online or over a mesh.
//!
//! An op is shown after every parent that is in the conversation. Among the ops that are ready, the
//! one with the smallest `(hlc, id)` goes next. A parent this device never received is ignored (it
//! cannot be waited for), and a malformed cycle falls back to `(hlc, id)` order.

use std::collections::HashSet;

use rusqlite::{params, Connection};

use super::{db_err, StoreError};

#[derive(Debug, Clone)]
pub(crate) struct Row {
    pub id: String,
    pub conversation_id: String,
    pub sender_id: String,
    pub body: String,
    pub sent_at: i64,
    pub local_state: String,
    pub hlc: Option<String>,
    pub parents: Vec<String>,
    pub op_id: Option<String>,
}

impl Row {
    /// Messages that did not come through the protocol (the sample chats, local-only sends) have no
    /// HLC: their display time stands in for the clock.
    fn key(&self) -> (String, String) {
        (
            self.hlc
                .clone()
                .unwrap_or_else(|| format!("{:013}.0000", self.sent_at.max(0))),
            self.id.clone(),
        )
    }
}

pub(crate) fn ordered(mut rows: Vec<Row>) -> Vec<Row> {
    rows.sort_by_key(Row::key);
    let present: HashSet<String> = rows.iter().filter_map(|r| r.op_id.clone()).collect();
    let mut waiting: Vec<Row> = rows;
    let mut placed: HashSet<String> = HashSet::new();
    let mut out = Vec::with_capacity(waiting.len());
    while !waiting.is_empty() {
        // `waiting` stays sorted by key, so the first ready row is the smallest.
        let ready = waiting.iter().position(|r| {
            r.parents
                .iter()
                .all(|p| !present.contains(p) || placed.contains(p) || Some(p) == r.op_id.as_ref())
        });
        let row = waiting.remove(ready.unwrap_or(0));
        if let Some(op) = &row.op_id {
            placed.insert(op.clone());
        }
        out.push(row);
    }
    out
}

/// The messages of a conversation's main timeline, in display order (replies are not part of it).
pub(crate) fn load_ordered(conn: &Connection, conversation_id: &str) -> Result<Vec<Row>, StoreError> {
    load(conn, "conversation_id = ?1 AND thread_root IS NULL", conversation_id)
}

/// A thread: the message it hangs from, then its replies, in display order.
pub(crate) fn load_thread(conn: &Connection, root_id: &str) -> Result<Vec<Row>, StoreError> {
    load(conn, "(id = ?1 OR thread_root = ?1)", root_id)
}

fn load(conn: &Connection, condition: &str, key: &str) -> Result<Vec<Row>, StoreError> {
    let mut statement = conn
        .prepare(&format!(
            "SELECT id, conversation_id, sender_id, body, sent_at, local_state, hlc, parents, op_id
             FROM messages WHERE {condition}"
        ))
        .map_err(db_err)?;
    let rows = statement
        .query_map(params![key], |r| {
            let parents: Option<String> = r.get(7)?;
            Ok(Row {
                id: r.get(0)?,
                conversation_id: r.get(1)?,
                sender_id: r.get(2)?,
                body: r.get(3)?,
                sent_at: r.get(4)?,
                local_state: r.get(5)?,
                hlc: r.get(6)?,
                parents: parents
                    .and_then(|p| serde_json::from_str(&p).ok())
                    .unwrap_or_default(),
                op_id: r.get(8)?,
            })
        })
        .map_err(db_err)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(db_err)?;
    Ok(ordered(rows))
}

/// The ops nothing else in the conversation lists as a parent yet, newest last, at most three:
/// what a new op names as its `parents`.
pub(crate) fn heads(conn: &Connection, conversation_id: &str) -> Result<Vec<String>, StoreError> {
    heads_of(load_ordered(conn, conversation_id)?)
}

/// The same for a thread.
pub(crate) fn thread_heads(conn: &Connection, root_id: &str) -> Result<Vec<String>, StoreError> {
    heads_of(load_thread(conn, root_id)?)
}

fn heads_of(rows: Vec<Row>) -> Result<Vec<String>, StoreError> {
    let referenced: HashSet<&String> = rows.iter().flat_map(|r| r.parents.iter()).collect();
    let mut heads: Vec<String> = rows
        .iter()
        .filter_map(|r| r.op_id.as_ref())
        .filter(|op| !referenced.contains(op))
        .cloned()
        .collect();
    let keep = heads.len().saturating_sub(3);
    Ok(heads.split_off(keep))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(id: &str, hlc: &str, parents: &[&str]) -> Row {
        Row {
            id: id.into(),
            conversation_id: "dm:x".into(),
            sender_id: "x".into(),
            body: id.into(),
            sent_at: 0,
            local_state: "received".into(),
            hlc: Some(hlc.into()),
            parents: parents.iter().map(|p| (*p).to_owned()).collect(),
            op_id: Some(id.into()),
        }
    }

    fn ids(rows: Vec<Row>) -> Vec<String> {
        ordered(rows).into_iter().map(|r| r.id).collect()
    }

    #[test]
    fn hlc_orders_unrelated_ops_and_the_op_id_breaks_a_tie() {
        let rows = vec![
            row("c", "0000000000002.0000", &[]),
            row("b", "0000000000001.0000", &[]),
            row("a", "0000000000001.0000", &[]),
        ];
        assert_eq!(ids(rows), vec!["a", "b", "c"]);
    }

    #[test]
    fn a_child_never_comes_before_its_parent_even_with_a_smaller_clock() {
        // The parent's device clock ran ahead: its hlc is larger than its child's.
        let rows = vec![
            row("child", "0000000000001.0000", &["parent"]),
            row("parent", "0000000000009.0000", &[]),
            row("other", "0000000000005.0000", &[]),
        ];
        assert_eq!(ids(rows), vec!["other", "parent", "child"]);
    }

    #[test]
    fn a_parent_that_never_arrived_is_not_waited_for() {
        let rows = vec![row("a", "0000000000001.0000", &["lost"]), row("b", "0000000000002.0000", &["a"])];
        assert_eq!(ids(rows), vec!["a", "b"]);
    }

    #[test]
    fn a_cycle_falls_back_to_clock_order() {
        let rows = vec![row("a", "0000000000002.0000", &["b"]), row("b", "0000000000001.0000", &["a"])];
        assert_eq!(ids(rows), vec!["b", "a"]);
    }

    #[test]
    fn the_order_is_the_same_whatever_order_the_rows_arrive_in() {
        let base = vec![
            row("a", "0000000000001.0000", &[]),
            row("b", "0000000000002.0000", &["a"]),
            row("c", "0000000000002.0001", &["a"]),
            row("d", "0000000000003.0000", &["b", "c"]),
        ];
        let expected = ids(base.clone());
        for rotation in 0..base.len() {
            let mut rows = base.clone();
            rows.rotate_left(rotation);
            assert_eq!(ids(rows.clone()), expected);
            rows.reverse();
            assert_eq!(ids(rows), expected);
        }
        assert_eq!(expected, vec!["a", "b", "c", "d"]);
    }
}
