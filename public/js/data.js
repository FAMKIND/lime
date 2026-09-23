'use strict';

// Accessors over the seed data embedded by seed-data.js (LIME-06).
// CURRENT_USER_ID is fixed — no user-switcher exists in this prototype.
const CURRENT_USER_ID = 'teacher-002';

const { teachers, conversations, messages } = window.LIME_SEED_DATA;

const teachersById = new Map(teachers.map((t) => [t.id, t]));

function getTeachers() {
  return teachers;
}

function getTeacherById(id) {
  return teachersById.get(id) || null;
}

function getConversationsForUser(userId) {
  return conversations.filter((c) => c.participants.includes(userId));
}

function getMessagesByConversation(conversationId) {
  return messages
    .filter((m) => m.conversation_id === conversationId)
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
}

function getDirectConversations() {
  return getConversationsForUser(CURRENT_USER_ID).filter((c) => c.type === 'direct');
}

function getGroupConversations() {
  return getConversationsForUser(CURRENT_USER_ID).filter((c) => c.type === 'group');
}

function getCommunityConversations() {
  return getConversationsForUser(CURRENT_USER_ID).filter((c) => c.type === 'community');
}

function getCurrentUser() {
  return getTeacherById(CURRENT_USER_ID);
}

// In-memory only (LIME-07) — pushed onto the same `messages` array
// getMessagesByConversation reads from, so it survives for the rest of
// this page load, but a reload discards it along with the rest of
// LIME_SEED_DATA. No backend yet, per the brief.
function sendMessage(conversationId, content) {
  const nextId = Math.max(...messages.map((m) => Number(m.id.split('-')[1]))) + 1;
  const message = {
    id: 'msg-' + String(nextId).padStart(3, '0'),
    conversation_id: conversationId,
    sender_id: CURRENT_USER_ID,
    content,
    type: 'text',
    created_at: new Date().toISOString(),
  };
  messages.push(message);
  return message;
}

function findMessageById(messageId) {
  return messages.find((m) => m.id === messageId) || null;
}

// Seed reactions ({emoji, count}) don't record *who* reacted, so "did the
// current user react with this emoji" can't be derived from the data
// itself (LIME-08) — tracked here instead, keyed per message+emoji.
const userReactedKeys = new Set();

function reactionKey(messageId, emoji) {
  return messageId + ':' + emoji;
}

function hasUserReacted(messageId, emoji) {
  return userReactedKeys.has(reactionKey(messageId, emoji));
}

function addReaction(messageId, emoji) {
  const message = findMessageById(messageId);
  if (!message) return null;
  if (!message.reactions) message.reactions = [];
  const existing = message.reactions.find((r) => r.emoji === emoji);
  if (existing) {
    existing.count += 1;
  } else {
    message.reactions.push({ emoji, count: 1 });
  }
  userReactedKeys.add(reactionKey(messageId, emoji));
  return message.reactions;
}

function removeReaction(messageId, emoji) {
  const message = findMessageById(messageId);
  if (!message || !message.reactions) return null;
  const existing = message.reactions.find((r) => r.emoji === emoji);
  if (existing) {
    existing.count -= 1;
    if (existing.count <= 0) {
      message.reactions = message.reactions.filter((r) => r.emoji !== emoji);
    }
  }
  userReactedKeys.delete(reactionKey(messageId, emoji));
  return message.reactions;
}

function toggleReaction(messageId, emoji) {
  return hasUserReacted(messageId, emoji) ? removeReaction(messageId, emoji) : addReaction(messageId, emoji);
}

// LIME-11. reply_count/last_reply_at on a parent message are seed-data
// metadata, not derived from anything — msg-003 claims reply_count:4 but
// only 1 real reply (msg-004) existed until this brief added 2 more, and
// even now the true count is 3, not 4. Never trusted for a displayed
// count; always computed live from the real reply_to relationships,
// same principle already applied to reactions (LIME-08).
function getRepliesForMessage(parentMessageId) {
  return messages
    .filter((m) => m.reply_to === parentMessageId)
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
}

function sendReply(parentMessageId, content) {
  const parent = findMessageById(parentMessageId);
  const nextId = Math.max(...messages.map((m) => Number(m.id.split('-')[1]))) + 1;
  const reply = {
    id: 'msg-' + String(nextId).padStart(3, '0'),
    conversation_id: parent ? parent.conversation_id : null,
    sender_id: CURRENT_USER_ID,
    content,
    type: 'text',
    reply_to: parentMessageId,
    created_at: new Date().toISOString(),
  };
  messages.push(reply);
  return reply;
}
