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
