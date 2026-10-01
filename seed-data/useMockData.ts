/**
 * Mock Data Hook for Rapid Prototyping
 *
 * Use this to get your prototype running without a database.
 * Just import and use - no setup required.
 *
 * Usage:
 *   import { useMockTeachers, useMockConversations, useMockMessages } from '@/seed-data/useMockData';
 *
 *   const teachers = useMockTeachers();
 *   const conversations = useMockConversations();
 *   const messages = useMockMessages(conversationId);
 */

import teachersData from './teachers.json';
import conversationsData from './conversations.json';
import messagesData from './messages.json';

// Types
export interface Teacher {
  id: string;
  display_name: string;
  initials: string;
  email: string;
  role: string;
  pronouns: string;
  school: string;
  grade_levels: string[];
  subjects: string[];
  bio: string;
  timezone: string;
  status: 'online' | 'offline' | 'busy';
}

export interface Conversation {
  id: string;
  type: 'direct' | 'group' | 'community';
  name: string | null;
  description?: string;
  participants: string[];
  created_by?: string;
  member_count?: number;
  avatar_color?: string;
  created_at: string;
  updated_at: string;
  // Computed
  lastMessage?: Message;
  unreadCount?: number;
}

export interface Message {
  id: string;
  conversation_id: string;
  sender_id: string;
  content: string | null;
  type: 'text' | 'voice' | 'location' | 'image';
  metadata?: {
    duration_seconds?: number;
    transcript?: string;
    latitude?: number;
    longitude?: number;
    place_name?: string;
  };
  reply_to?: string;
  reply_count?: number;
  last_reply_at?: string;
  reactions?: Array<{ emoji: string; count: number }>;
  created_at: string;
  // Computed
  sender?: Teacher;
}

// Data accessors
export const teachers: Teacher[] = teachersData.teachers as Teacher[];
export const conversations: Conversation[] = conversationsData.conversations as Conversation[];
export const messages: Message[] = messagesData.messages as Message[];

// Helper functions
export function getTeacherById(id: string): Teacher | undefined {
  return teachers.find(t => t.id === id);
}

export function getConversationById(id: string): Conversation | undefined {
  return conversations.find(c => c.id === id);
}

export function getMessagesByConversation(conversationId: string): Message[] {
  return messages
    .filter(m => m.conversation_id === conversationId)
    .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
}

export function getLastMessage(conversationId: string): Message | undefined {
  const convMessages = getMessagesByConversation(conversationId);
  return convMessages[convMessages.length - 1];
}

export function getConversationParticipants(conversationId: string): Teacher[] {
  const conv = getConversationById(conversationId);
  if (!conv) return [];
  return conv.participants
    .map(id => getTeacherById(id))
    .filter((t): t is Teacher => t !== undefined);
}

export function getDirectConversations(): Conversation[] {
  return conversations.filter(c => c.type === 'direct');
}

export function getGroupConversations(): Conversation[] {
  return conversations.filter(c => c.type === 'group');
}

export function getCommunityConversations(): Conversation[] {
  return conversations.filter(c => c.type === 'community');
}

// Enriched data (with computed fields)
export function getEnrichedConversations(): Conversation[] {
  return conversations.map(conv => ({
    ...conv,
    lastMessage: getLastMessage(conv.id),
    unreadCount: Math.floor(Math.random() * 5), // Fake unread count for demo
  }));
}

export function getEnrichedMessages(conversationId: string): Message[] {
  return getMessagesByConversation(conversationId).map(msg => ({
    ...msg,
    sender: getTeacherById(msg.sender_id),
  }));
}

// For displaying conversation names (handles direct messages)
export function getConversationDisplayName(
  conversationId: string,
  currentUserId: string
): string {
  const conv = getConversationById(conversationId);
  if (!conv) return 'Unknown';

  if (conv.name) return conv.name;

  // For direct messages, show the other person's name
  if (conv.type === 'direct') {
    const otherId = conv.participants.find(id => id !== currentUserId);
    const other = otherId ? getTeacherById(otherId) : undefined;
    return other?.display_name || 'Unknown';
  }

  // For unnamed groups, list participants
  const names = conv.participants
    .map(id => getTeacherById(id)?.display_name)
    .filter(Boolean)
    .slice(0, 3);

  if (names.length < conv.participants.length) {
    return `${names.join(', ')} & ${conv.participants.length - names.length} more`;
  }

  return names.join(', ');
}

// React hooks (if using React)
export function useMockTeachers(): Teacher[] {
  return teachers;
}

export function useMockConversations(type?: 'direct' | 'group' | 'community'): Conversation[] {
  if (type === 'direct') return getDirectConversations();
  if (type === 'group') return getGroupConversations();
  if (type === 'community') return getCommunityConversations();
  return getEnrichedConversations();
}

export function useMockMessages(conversationId: string): Message[] {
  return getEnrichedMessages(conversationId);
}

export function useMockCurrentUser(): Teacher {
  // Default to Shem Rajoon as the current user for demo
  return teachers.find(t => t.id === 'teacher-002')!;
}

// Starred/Recent teachers (for the horizontal scroll in your Figma)
export function getStarredTeachers(currentUserId: string): Teacher[] {
  // Get teachers the user has recent DMs with
  const recentDMs = getDirectConversations()
    .filter(c => c.participants.includes(currentUserId))
    .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
    .slice(0, 5);

  return recentDMs
    .map(conv => {
      const otherId = conv.participants.find(id => id !== currentUserId);
      return otherId ? getTeacherById(otherId) : undefined;
    })
    .filter((t): t is Teacher => t !== undefined);
}

export function getRecentTeachers(currentUserId: string): Teacher[] {
  return getStarredTeachers(currentUserId);
}

// Format timestamp for display
export function formatMessageTime(timestamp: string): string {
  const date = new Date(timestamp);
  const now = new Date();
  const diffDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));

  if (diffDays === 0) {
    return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  } else if (diffDays === 1) {
    return 'Yesterday';
  } else if (diffDays < 7) {
    return date.toLocaleDateString('en-US', { weekday: 'short' });
  } else {
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }
}
