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
