/**
 * Supabase Seed Script for Lime
 *
 * Usage with Claude Code:
 *   "Run the seed script to populate the database"
 *
 * Or manually:
 *   npx ts-node seed-data/seed.ts
 */

import { createClient } from '@supabase/supabase-js';
import teachers from './teachers.json';
import conversations from './conversations.json';
import messages from './messages.json';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Demo defaults (LIME-25, mirrored from public/js/local-adapter.js's own
// DEMO_MEMBER_STATE) so a database seed starts with the same two
// conversations starred for the demo user, matching the local prototype.
const DEMO_MEMBER_STATE: Record<string, Record<string, { starred?: boolean }>> = {
  'teacher-002': {
    'conv-001': { starred: true },
    'conv-010': { starred: true },
  },
};

async function seed() {
  console.log('🌱 Starting seed...\n');

  // Clear existing data (in reverse order of dependencies)
  console.log('Clearing existing data...');
  await supabase.from('message_reactions').delete().neq('id', '');
  await supabase.from('messages').delete().neq('id', '');
  await supabase.from('conversation_members').delete().neq('conversation_id', '');
  await supabase.from('conversations').delete().neq('id', '');
  await supabase.from('profiles').delete().neq('id', '');

  // Seed teachers/profiles
  console.log(`\n👩‍🏫 Seeding ${teachers.teachers.length} teachers...`);
  for (const teacher of teachers.teachers) {
    const { error } = await supabase.from('profiles').insert({
      id: teacher.id,
      display_name: teacher.display_name,
      email: teacher.email,
      role: teacher.role,
      pronouns: teacher.pronouns,
      school: teacher.school,
      grade_levels: teacher.grade_levels,
      subjects: teacher.subjects,
      bio: teacher.bio,
      timezone: teacher.timezone,
      status: teacher.status,
      avatar_url: null, // Could generate from initials
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });

    if (error) {
      console.error(`  ❌ Failed to insert ${teacher.display_name}:`, error.message);
    } else {
      console.log(`  ✓ ${teacher.display_name}`);
    }
  }

  // Seed conversations
  console.log(`\n💬 Seeding ${conversations.conversations.length} conversations...`);
  for (const conv of conversations.conversations) {
    const { error: convError } = await supabase.from('conversations').insert({
      id: conv.id,
      type: conv.type,
      name: conv.name,
      description: conv.description || null,
      created_by: conv.created_by || conv.participants[0],
      created_at: conv.created_at,
      updated_at: conv.updated_at,
    });

    if (convError) {
      console.error(`  ❌ Failed to insert conversation ${conv.id}:`, convError.message);
      continue;
    }

    // Add members
    for (const participantId of conv.participants) {
      const demo = DEMO_MEMBER_STATE[participantId]?.[conv.id] ?? {};
      await supabase.from('conversation_members').insert({
        conversation_id: conv.id,
        user_id: participantId,
        role: participantId === conv.created_by ? 'owner' : 'member',
        starred: demo.starred ?? false,
        joined_at: conv.created_at,
      });
    }

    console.log(`  ✓ ${conv.name || conv.type + ' ' + conv.id}`);
  }

  // Seed messages
  console.log(`\n📝 Seeding ${messages.messages.length} messages...`);
  for (const msg of messages.messages) {
    const { error } = await supabase.from('messages').insert({
      id: msg.id,
      conversation_id: msg.conversation_id,
      sender_id: msg.sender_id,
      content: msg.content,
      type: msg.type,
      metadata: msg.metadata || null,
      reply_to: msg.reply_to || null,
      created_at: msg.created_at,
      updated_at: msg.created_at,
    });

    if (error) {
      console.error(`  ❌ Failed to insert message ${msg.id}:`, error.message);
    }

    // Add reactions if present
    if (msg.reactions) {
      for (const reaction of msg.reactions) {
        // The reactor rule (LIME-24a-fix, applied here in LIME-24b): a
        // reaction's reactors are the conversation's distinct members, in
        // participant order, sliced to min(count, member count) — a
        // reaction can't have more reactors than the conversation has
        // members. The old version here selected from message senders
        // without deduping, which could both exceed the conversation's
        // real membership and insert the same (message, user, emoji)
        // triple more than once, violating message_reactions' own
        // primary key. This matches LocalAdapter's own reactor logic
        // exactly, so a local seed and a database seed agree.
        const reactedConversation = conversations.conversations.find(c => c.id === msg.conversation_id);
        const memberIds = reactedConversation ? reactedConversation.participants : [];
        const reactors = memberIds.slice(0, Math.min(reaction.count, memberIds.length));

        for (const reactorId of reactors) {
          await supabase.from('message_reactions').insert({
            message_id: msg.id,
            user_id: reactorId,
            emoji: reaction.emoji,
            created_at: msg.created_at,
          });
        }
      }
    }
  }
  console.log(`  ✓ ${messages.messages.length} messages inserted`);

  console.log('\n✅ Seed complete!');
  console.log(`
Summary:
  - ${teachers.teachers.length} teachers
  - ${conversations.conversations.length} conversations
  - ${messages.messages.length} messages
  `);
}

seed().catch(console.error);
