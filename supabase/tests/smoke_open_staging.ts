// Read-mostly staging smoke test for open posts (LIME-210a), run with open_posts_enabled OFF: ./supabase/smoke-open-staging.sh
import { assertEquals } from "jsr:@std/assert@1";
import { admin, call, deleteUser, newUser } from "./helpers.ts";

const user = await newUser();
try {
  const { data: bucket, error } = await admin.storage.getBucket("open-files");
  assertEquals([error, bucket?.public], [null, true], "the open-files bucket exists and is public");
  const { data: flag } = await admin.from("server_flags").select("enabled").eq("name", "open_posts_enabled").single();
  assertEquals(flag?.enabled, false, "the flag is off");
  assertEquals((await call("open-post-get", null, { post_id: crypto.randomUUID() })).status, 404, "open-post-get needs no session");
  const feed = await call("open-feed", user.token, { since: 0 });
  assertEquals([feed.status, feed.body.enabled, feed.body.items], [200, false, []]);
  const put = await call("open-file", user.token, { action: "put", file_id: crypto.randomUUID(), size: 10, mime: "image/jpeg" });
  assertEquals([put.status, put.body.error], [403, "open_posts_disabled"]);
  const pub = await call("open-post", user.token, { action: "publish", payload: "{}", signature: "x", cert: {} });
  assertEquals([pub.status, pub.body.error], [403, "open_posts_disabled"]);
  assertEquals((await call("moderation-act", user.token, { action: "hide_open_post", target: crypto.randomUUID() })).status, 403, "not a moderator");
  const jamId = crypto.randomUUID();
  assertEquals((await call("jam-page", user.token, { action: "set", jam_id: jamId, title: "Smoke", about: "", topics: [], post_count: 0, has_community: true })).status, 200);
  assertEquals((await call("jam-page", user.token, { action: "get", jam_id: jamId })).body.jam.has_community, true, "jam-page carries has_community");
  console.log("open posts staging smoke: ok (flag still off)");
} finally {
  await deleteUser(user);
}
