# Lime Seed Data

Realistic demo data for populating your Lime prototype.

## Files

| File | Records | Description |
|------|---------|-------------|
| `teachers.json` | 25 | Teacher profiles with diverse backgrounds, subjects, schools |
| `conversations.json` | 18 | Direct messages, group chats, and community channels |
| `messages.json` | 50+ | Realistic message threads across all conversation types |

## Quick Usage with Claude Code

When working in Cursor with Claude Code, you can say:

> "Read the seed data from seed-data/teachers.json and create a Supabase seed script"

Or for quick prototyping without a database:

> "Use the seed data from seed-data/ to populate the mock data in our prototype"

## Data Structure

### Teachers (`teachers.json`)

```typescript
interface Teacher {
  id: string;              // "teacher-001"
  display_name: string;    // "Jean Chung"
  initials: string;        // "JC"
  email: string;
  role: string;            // "Head of FAM"
  pronouns: string;        // "she/her/hers"
  school: string;          // "PS 113"
  grade_levels: string[];  // ["6", "7", "8"]
  subjects: string[];      // ["Family and Consumer Science", "Health"]
  bio: string;
  timezone: string;        // "America/New_York"
  status: "online" | "offline" | "busy";
}
```

### Conversations (`conversations.json`)

```typescript
interface Conversation {
  id: string;
  type: "direct" | "group" | "community";
  name: string | null;        // null for direct messages
  description?: string;
  participants: string[];     // teacher IDs
  created_by?: string;
  member_count?: number;      // for communities
  avatar_color?: string;      // for communities
  created_at: string;
  updated_at: string;
}
```

### Messages (`messages.json`)

```typescript
interface Message {
  id: string;
  conversation_id: string;
  sender_id: string;
  content: string | null;
  type: "text" | "voice" | "location" | "image";
  metadata?: {
    // For voice messages
    duration_seconds?: number;
    transcript?: string;
    // For location
    latitude?: number;
    longitude?: number;
    place_name?: string;
  };
  reply_to?: string;         // parent message ID for threads
  reply_count?: number;
  last_reply_at?: string;
  reactions?: Array<{emoji: string; count: number}>;
  created_at: string;
}
```

## Demo Scenarios Included

### Direct Message Threads
- **Jean ↔ Shem**: Interdisciplinary project planning (math + life skills)
- **Jean ↔ Valene**: Curriculum concerns and advocacy
- **Jean ↔ Mary**: Classroom management strategies
- **Shem ↔ Alexi**: Special education math support

### Group Chats
- **PS 113 7th Grade Team**: Team meeting coordination
- **Math Teachers NYC**: Cross-school collaboration on Desmos
- **STEM Squad**: Robotics celebration and cross-school projects
- **New Teacher Support**: First-year teacher check-ins and self-care
- **Jean, Mary, Jimin & Me**: Social planning (trivia night)

### Community Channels
- **Black Teachers NY**: Book study announcement
- **PS 113**: Staff meeting updates
- **Book Club**: Discussion of "Culturally Responsive Teaching"
- **Resources**: Curriculum sharing
- **NYC STEAM Teachers**: Maker Faire meetup planning
- **Local Meetups**: In-person gatherings
- **Announcements**: Platform updates
- **PD**: Professional development

## Conversation Types in Figma

Matches your Figma designs:
- **Teachers tab**: Direct 1:1 messages (conv-001 through conv-005)
- **Group Chats tab**: Small groups (conv-006 through conv-010)
- **Community tab**: Large communities (conv-community-001 through conv-community-009)

## Schools Represented

- PS 113 (main school for demo)
- Brooklyn Charter Academy
- Harlem Prep
- Queens Academy of Arts
- Sunset Park Elementary
- Bronx STEM Academy
- Flushing International HS
- Tech Prep Middle School
- Harlem Village Academy
- Washington Heights MS
- Stuyvesant High School
- And 10+ more...

## Subjects Covered

Math, Science, English, Art, Special Education, STEM/Robotics, ESL, Technology, Social Studies, Music, PE, Chemistry, Physics, Drama, Biology, Engineering, Counseling, and more.
