'use strict';

// Embedded copy of seed-data/*.json (LIME-06). fetch() of a local JSON
// file from a file:// page is blocked by both Chrome and Safari — verified
// empirically, not assumed — so this project's own documented workflow
// (README: `open public/index.html`) can never actually fetch() anything.
// Embedding the data as a script keeps it available synchronously with no
// server, matching the vanilla-JS/file:// constraint. seed-data/*.json
// remains the source of truth; this file is a generated mirror of it.
window.LIME_SEED_DATA = {
  "teachers": [
    {
      "id": "teacher-001",
      "display_name": "Jean Chung",
      "initials": "JC",
      "email": "jean@famkind.com",
      "role": "Head of FAM",
      "pronouns": "she/her/hers",
      "school": "PS 113",
      "grade_levels": [
        "6",
        "7",
        "8"
      ],
      "subjects": [
        "Family and Consumer Science",
        "Health"
      ],
      "bio": "15 years teaching life skills. Passionate about practical education that prepares students for real life.",
      "timezone": "America/New_York",
      "status": "busy"
    },
    {
      "id": "teacher-002",
      "display_name": "Shem Rajoon",
      "initials": "SR",
      "email": "shem@famkind.com",
      "role": "Math Teacher",
      "pronouns": "he/him/his",
      "school": "PS 113",
      "grade_levels": [
        "7",
        "8"
      ],
      "subjects": [
        "Algebra",
        "Geometry"
      ],
      "bio": "Making math accessible and fun. Former engineer turned educator.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-003",
      "display_name": "Valene Rajoon",
      "initials": "VR",
      "email": "valene@famkind.com",
      "role": "Science Teacher",
      "pronouns": "she/her/hers",
      "school": "Brooklyn Charter Academy",
      "grade_levels": [
        "5",
        "6"
      ],
      "subjects": [
        "General Science",
        "Environmental Studies"
      ],
      "bio": "Hands-on science advocate. Love field trips and experiments!",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-004",
      "display_name": "Mary Lee",
      "initials": "ML",
      "email": "mary@famkind.com",
      "role": "English Teacher",
      "pronouns": "she/her/hers",
      "school": "Harlem Prep",
      "grade_levels": [
        "9",
        "10"
      ],
      "subjects": [
        "English Literature",
        "Creative Writing"
      ],
      "bio": "Words change worlds. Building confident writers one draft at a time.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-005",
      "display_name": "Jimin Park",
      "initials": "JP",
      "email": "jimin@famkind.com",
      "role": "Art Teacher",
      "pronouns": "they/them",
      "school": "Queens Academy of Arts",
      "grade_levels": [
        "K",
        "1",
        "2",
        "3"
      ],
      "subjects": [
        "Visual Arts",
        "Art History"
      ],
      "bio": "Every child is an artist. My job is to help them stay that way.",
      "timezone": "America/New_York",
      "status": "offline"
    },
    {
      "id": "teacher-006",
      "display_name": "Alexi Daily",
      "initials": "AD",
      "email": "alexi@famkind.com",
      "role": "Special Education",
      "pronouns": "she/her/hers",
      "school": "Sunset Park Elementary",
      "grade_levels": [
        "3",
        "4",
        "5"
      ],
      "subjects": [
        "Resource Room",
        "Inclusion Support"
      ],
      "bio": "All learners deserve access. IEP specialist and inclusion advocate.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-007",
      "display_name": "Amanda Civilian",
      "initials": "AC",
      "email": "amanda@famkind.com",
      "role": "STEM Coordinator",
      "pronouns": "she/her/hers",
      "school": "Bronx STEM Academy",
      "grade_levels": [
        "6",
        "7",
        "8"
      ],
      "subjects": [
        "Robotics",
        "Computer Science"
      ],
      "bio": "Building the next generation of problem solvers. Robotics club advisor.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-008",
      "display_name": "Eun Jean",
      "initials": "EJ",
      "email": "eun@famkind.com",
      "role": "ESL Teacher",
      "pronouns": "she/her/hers",
      "school": "Flushing International HS",
      "grade_levels": [
        "9",
        "10",
        "11",
        "12"
      ],
      "subjects": [
        "ESL",
        "ENL"
      ],
      "bio": "Multilingual educator. Helping newcomers find their voice in English.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-009",
      "display_name": "Kai Nakamura",
      "initials": "KN",
      "email": "kai@famkind.com",
      "role": "Technology Teacher",
      "pronouns": "he/him/his",
      "school": "Tech Prep Middle School",
      "grade_levels": [
        "6",
        "7",
        "8"
      ],
      "subjects": [
        "Digital Literacy",
        "Coding"
      ],
      "bio": "Teaching kids to be creators, not just consumers of technology.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-010",
      "display_name": "Priya Osei",
      "initials": "PO",
      "email": "priya@famkind.com",
      "role": "Social Studies Teacher",
      "pronouns": "she/her/hers",
      "school": "Harlem Village Academy",
      "grade_levels": [
        "7",
        "8"
      ],
      "subjects": [
        "World History",
        "Geography"
      ],
      "bio": "History teacher who believes in learning from the past to shape the future.",
      "timezone": "America/New_York",
      "status": "offline"
    },
    {
      "id": "teacher-011",
      "display_name": "Tomás Villareal",
      "initials": "TV",
      "email": "tomas@famkind.com",
      "role": "Music Teacher",
      "pronouns": "he/him/his",
      "school": "Washington Heights MS",
      "grade_levels": [
        "6",
        "7",
        "8"
      ],
      "subjects": [
        "Band",
        "Music Theory"
      ],
      "bio": "Former jazz musician. Every kid deserves to experience making music.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-012",
      "display_name": "Ingrid Solberg",
      "initials": "IS",
      "email": "ingrid@famkind.com",
      "role": "PE Teacher",
      "pronouns": "she/her/hers",
      "school": "Norwood Academy",
      "grade_levels": [
        "K",
        "1",
        "2",
        "3",
        "4",
        "5"
      ],
      "subjects": [
        "Physical Education",
        "Health"
      ],
      "bio": "Movement is medicine. Building healthy habits that last a lifetime.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-013",
      "display_name": "Marcus Thompson",
      "initials": "MT",
      "email": "marcus@famkind.com",
      "role": "History Teacher",
      "pronouns": "he/him/his",
      "school": "Bed-Stuy Collegiate",
      "grade_levels": [
        "9",
        "10",
        "11"
      ],
      "subjects": [
        "US History",
        "African American Studies"
      ],
      "bio": "Teaching history that reflects all of us. Curriculum writer and speaker.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-014",
      "display_name": "Sofia Martinez",
      "initials": "SM",
      "email": "sofia@famkind.com",
      "role": "Bilingual Teacher",
      "pronouns": "she/her/hers",
      "school": "Elmhurst Community School",
      "grade_levels": [
        "2",
        "3"
      ],
      "subjects": [
        "Dual Language",
        "Spanish"
      ],
      "bio": "Bilingualism is a superpower. Teaching in two languages, one heart.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-015",
      "display_name": "David Chen",
      "initials": "DC",
      "email": "david@famkind.com",
      "role": "Physics Teacher",
      "pronouns": "he/him/his",
      "school": "Stuyvesant High School",
      "grade_levels": [
        "11",
        "12"
      ],
      "subjects": [
        "AP Physics",
        "Engineering"
      ],
      "bio": "MIT alum. Making physics intuitive through hands-on experiments.",
      "timezone": "America/New_York",
      "status": "offline"
    },
    {
      "id": "teacher-016",
      "display_name": "Aisha Johnson",
      "initials": "AJ",
      "email": "aisha@famkind.com",
      "role": "Counselor",
      "pronouns": "she/her/hers",
      "school": "Medgar Evers Prep",
      "grade_levels": [
        "9",
        "10",
        "11",
        "12"
      ],
      "subjects": [
        "Guidance",
        "College Prep"
      ],
      "bio": "Every student has a path to success. I help them find it.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-017",
      "display_name": "Michael O'Brien",
      "initials": "MO",
      "email": "michael@famkind.com",
      "role": "Chemistry Teacher",
      "pronouns": "he/him/his",
      "school": "St. Patrick's Academy",
      "grade_levels": [
        "10",
        "11",
        "12"
      ],
      "subjects": [
        "Chemistry",
        "AP Chemistry"
      ],
      "bio": "Chemistry is just cooking with consequences. Safety first, fun always.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-018",
      "display_name": "Fatima Al-Hassan",
      "initials": "FA",
      "email": "fatima@famkind.com",
      "role": "Math Teacher",
      "pronouns": "she/her/hers",
      "school": "Bayside High School",
      "grade_levels": [
        "9",
        "10"
      ],
      "subjects": [
        "Algebra II",
        "Statistics"
      ],
      "bio": "Math anxiety ends here. Building confidence one problem at a time.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-019",
      "display_name": "James Wright",
      "initials": "JW",
      "email": "james@famkind.com",
      "role": "Reading Specialist",
      "pronouns": "he/him/his",
      "school": "East Harlem Scholars",
      "grade_levels": [
        "K",
        "1",
        "2"
      ],
      "subjects": [
        "Literacy",
        "Phonics"
      ],
      "bio": "Literacy changes lives. Every child can learn to read with the right support.",
      "timezone": "America/New_York",
      "status": "offline"
    },
    {
      "id": "teacher-020",
      "display_name": "Nina Petrova",
      "initials": "NP",
      "email": "nina@famkind.com",
      "role": "Drama Teacher",
      "pronouns": "she/her/hers",
      "school": "Brighton Beach Academy",
      "grade_levels": [
        "6",
        "7",
        "8"
      ],
      "subjects": [
        "Theater",
        "Public Speaking"
      ],
      "bio": "Former Broadway performer. Teaching confidence through performance.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-021",
      "display_name": "Carlos Rivera",
      "initials": "CR",
      "email": "carlos@famkind.com",
      "role": "Science Teacher",
      "pronouns": "he/him/his",
      "school": "Hunts Point Academy",
      "grade_levels": [
        "7",
        "8"
      ],
      "subjects": [
        "Biology",
        "Life Science"
      ],
      "bio": "Urban gardener and science teacher. Learning happens everywhere.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-022",
      "display_name": "Jasmine Williams",
      "initials": "JWI",
      "email": "jasmine@famkind.com",
      "role": "Math Coach",
      "pronouns": "she/her/hers",
      "school": "Canarsie Collegiate",
      "grade_levels": [
        "6",
        "7",
        "8"
      ],
      "subjects": [
        "Math Intervention",
        "PD"
      ],
      "bio": "Supporting teachers to support students. Math coaching is my passion.",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-023",
      "display_name": "Robert Kim",
      "initials": "RK",
      "email": "robert@famkind.com",
      "role": "Social Studies Teacher",
      "pronouns": "he/him/his",
      "school": "Beacon High School",
      "grade_levels": [
        "9",
        "10",
        "11"
      ],
      "subjects": [
        "Government",
        "Economics"
      ],
      "bio": "Teaching civic engagement in action. Mock trial advisor.",
      "timezone": "America/New_York",
      "status": "offline"
    },
    {
      "id": "teacher-024",
      "display_name": "Grace Okonkwo",
      "initials": "GO",
      "email": "grace@famkind.com",
      "role": "Biology Teacher",
      "pronouns": "she/her/hers",
      "school": "Liberty Prep Academy",
      "grade_levels": [
        "9",
        "10"
      ],
      "subjects": [
        "Biology",
        "Environmental Science"
      ],
      "bio": "Nature lover and science educator. Field trip enthusiast!",
      "timezone": "America/New_York",
      "status": "online"
    },
    {
      "id": "teacher-025",
      "display_name": "Derek Washington",
      "initials": "DW",
      "email": "derek@famkind.com",
      "role": "Engineering Teacher",
      "pronouns": "he/him/his",
      "school": "Brooklyn Tech",
      "grade_levels": [
        "10",
        "11",
        "12"
      ],
      "subjects": [
        "Engineering Design",
        "CAD"
      ],
      "bio": "Building the builders. FIRST Robotics coach and maker space coordinator.",
      "timezone": "America/New_York",
      "status": "online"
    }
  ],
  "conversations": [
    {
      "id": "conv-001",
      "type": "direct",
      "name": null,
      "participants": [
        "teacher-001",
        "teacher-002"
      ],
      "created_at": "2025-06-15T10:00:00Z",
      "updated_at": "2025-07-08T15:30:00Z"
    },
    {
      "id": "conv-002",
      "type": "direct",
      "name": null,
      "participants": [
        "teacher-001",
        "teacher-003"
      ],
      "created_at": "2025-05-20T14:00:00Z",
      "updated_at": "2025-07-07T11:30:00Z"
    },
    {
      "id": "conv-003",
      "type": "direct",
      "name": null,
      "participants": [
        "teacher-001",
        "teacher-004"
      ],
      "created_at": "2025-06-01T09:00:00Z",
      "updated_at": "2025-07-06T16:45:00Z"
    },
    {
      "id": "conv-004",
      "type": "direct",
      "name": null,
      "participants": [
        "teacher-002",
        "teacher-006"
      ],
      "created_at": "2025-06-10T11:00:00Z",
      "updated_at": "2025-07-08T09:15:00Z"
    },
    {
      "id": "conv-005",
      "type": "direct",
      "name": null,
      "participants": [
        "teacher-002",
        "teacher-009"
      ],
      "created_at": "2025-06-25T13:00:00Z",
      "updated_at": "2025-07-07T14:20:00Z"
    },
    {
      "id": "conv-006",
      "type": "group",
      "name": "PS 113 7th Grade Team",
      "description": "Coordination for 7th grade teachers",
      "participants": [
        "teacher-001",
        "teacher-002",
        "teacher-010",
        "teacher-013"
      ],
      "created_by": "teacher-001",
      "created_at": "2025-05-01T08:00:00Z",
      "updated_at": "2025-07-08T12:00:00Z"
    },
    {
      "id": "conv-007",
      "type": "group",
      "name": "Math Teachers NYC",
      "description": "Cross-school math collaboration",
      "participants": [
        "teacher-002",
        "teacher-018",
        "teacher-022",
        "teacher-015"
      ],
      "created_by": "teacher-002",
      "created_at": "2025-04-15T10:00:00Z",
      "updated_at": "2025-07-07T16:30:00Z"
    },
    {
      "id": "conv-008",
      "type": "group",
      "name": "STEM Squad",
      "description": "Science, tech, engineering, and math teachers sharing ideas",
      "participants": [
        "teacher-007",
        "teacher-009",
        "teacher-015",
        "teacher-021",
        "teacher-025"
      ],
      "created_by": "teacher-007",
      "created_at": "2025-03-10T14:00:00Z",
      "updated_at": "2025-07-08T10:45:00Z"
    },
    {
      "id": "conv-009",
      "type": "group",
      "name": "New Teacher Support",
      "description": "Mentorship and support for teachers in their first 3 years",
      "participants": [
        "teacher-006",
        "teacher-008",
        "teacher-014",
        "teacher-016",
        "teacher-022"
      ],
      "created_by": "teacher-016",
      "created_at": "2025-02-20T09:00:00Z",
      "updated_at": "2025-07-06T11:20:00Z"
    },
    {
      "id": "conv-010",
      "type": "group",
      "name": "Jean, Mary, Jimin & Me",
      "description": null,
      "participants": [
        "teacher-001",
        "teacher-004",
        "teacher-005",
        "teacher-002"
      ],
      "created_by": "teacher-002",
      "created_at": "2025-06-01T15:00:00Z",
      "updated_at": "2025-07-07T18:00:00Z"
    },
    {
      "id": "conv-011",
      "type": "group",
      "name": "PS 113 Staff Room",
      "description": "Staff room banter and building logistics",
      "participants": [
        "teacher-002",
        "teacher-001",
        "teacher-010",
        "teacher-013",
        "teacher-014",
        "teacher-015",
        "teacher-016",
        "teacher-018",
        "teacher-022",
        "teacher-024"
      ],
      "created_by": "teacher-001",
      "created_at": "2025-05-15T08:00:00Z",
      "updated_at": "2025-07-08T12:15:00Z"
    },
    {
      "id": "conv-community-001",
      "type": "community",
      "name": "Black Teachers NY",
      "description": "A space for Black educators in New York to connect, share resources, and support each other.",
      "avatar_color": "#8B4513",
      "participants": [
        "teacher-013",
        "teacher-016",
        "teacher-019",
        "teacher-022",
        "teacher-025",
        "teacher-006"
      ],
      "created_by": "teacher-013",
      "member_count": 847,
      "created_at": "2024-09-01T10:00:00Z",
      "updated_at": "2025-07-08T14:30:00Z"
    },
    {
      "id": "conv-community-002",
      "type": "community",
      "name": "PS 113",
      "description": "Official community for PS 113 faculty and staff",
      "avatar_color": "#2E8B57",
      "participants": [
        "teacher-001",
        "teacher-002",
        "teacher-010"
      ],
      "created_by": "teacher-001",
      "member_count": 62,
      "created_at": "2024-08-15T08:00:00Z",
      "updated_at": "2025-07-08T09:00:00Z"
    },
    {
      "id": "conv-community-003",
      "type": "community",
      "name": "Book Club",
      "description": "Monthly book discussions for educators. Currently reading: 'Culturally Responsive Teaching and the Brain'",
      "avatar_color": "#6B5B95",
      "participants": [
        "teacher-004",
        "teacher-016",
        "teacher-020",
        "teacher-014"
      ],
      "created_by": "teacher-004",
      "member_count": 234,
      "created_at": "2024-10-01T12:00:00Z",
      "updated_at": "2025-07-05T20:00:00Z"
    },
    {
      "id": "conv-community-004",
      "type": "community",
      "name": "Resources",
      "description": "Share and discover teaching resources, lesson plans, and materials",
      "avatar_color": "#3498DB",
      "participants": [
        "teacher-007",
        "teacher-009",
        "teacher-022",
        "teacher-003"
      ],
      "created_by": "teacher-007",
      "member_count": 1523,
      "created_at": "2024-06-01T10:00:00Z",
      "updated_at": "2025-07-08T11:15:00Z"
    },
    {
      "id": "conv-community-005",
      "type": "community",
      "name": "NYC STEAM Teachers",
      "description": "Connecting STEAM educators across NYC public schools",
      "avatar_color": "#E74C3C",
      "participants": [
        "teacher-007",
        "teacher-009",
        "teacher-015",
        "teacher-021",
        "teacher-025",
        "teacher-017"
      ],
      "created_by": "teacher-025",
      "member_count": 412,
      "created_at": "2024-07-15T14:00:00Z",
      "updated_at": "2025-07-07T16:45:00Z"
    },
    {
      "id": "conv-community-006",
      "type": "community",
      "name": "Local Meetups",
      "description": "Organize and find in-person teacher meetups in your area",
      "avatar_color": "#F39C12",
      "participants": [
        "teacher-011",
        "teacher-014",
        "teacher-020",
        "teacher-003"
      ],
      "created_by": "teacher-011",
      "member_count": 189,
      "created_at": "2025-01-10T11:00:00Z",
      "updated_at": "2025-07-06T13:30:00Z"
    },
    {
      "id": "conv-community-007",
      "type": "community",
      "name": "Announcements",
      "description": "Official announcements from the Lime team",
      "avatar_color": "#1ABC9C",
      "participants": [
        "teacher-001",
        "teacher-002"
      ],
      "created_by": "teacher-001",
      "member_count": 4521,
      "created_at": "2024-01-01T00:00:00Z",
      "updated_at": "2025-07-01T10:00:00Z"
    },
    {
      "id": "conv-community-008",
      "type": "community",
      "name": "PD",
      "description": "Professional development opportunities, workshops, and certifications",
      "avatar_color": "#9B59B6",
      "participants": [
        "teacher-016",
        "teacher-022",
        "teacher-006"
      ],
      "created_by": "teacher-016",
      "member_count": 876,
      "created_at": "2024-05-20T09:00:00Z",
      "updated_at": "2025-07-08T08:30:00Z"
    },
    {
      "id": "conv-community-009",
      "type": "community",
      "name": "Bulletin Board",
      "description": "General discussion and community updates",
      "avatar_color": "#34495E",
      "participants": [
        "teacher-001",
        "teacher-002",
        "teacher-003",
        "teacher-004"
      ],
      "created_by": "teacher-001",
      "member_count": 3210,
      "created_at": "2024-01-15T10:00:00Z",
      "updated_at": "2025-07-08T15:00:00Z"
    }
  ],
  "messages": [
    {
      "id": "msg-001",
      "conversation_id": "conv-001",
      "sender_id": "teacher-002",
      "content": "Hey Jean! Quick question about the interdisciplinary project we discussed. Do you have time to meet this week?",
      "type": "text",
      "created_at": "2025-07-07T11:30:00Z"
    },
    {
      "id": "msg-002",
      "conversation_id": "conv-001",
      "sender_id": "teacher-001",
      "content": "Hi Shem! Yes, I'd love to connect. How about Wednesday during our shared prep period?",
      "type": "text",
      "created_at": "2025-07-07T11:32:00Z"
    },
    {
      "id": "msg-003",
      "conversation_id": "conv-001",
      "sender_id": "teacher-002",
      "content": "Perfect! I was thinking we could do a unit where students calculate nutritional values and budgets for meal planning. Combines your life skills with my math curriculum.",
      "type": "text",
      "created_at": "2025-07-07T11:35:00Z",
      "reply_count": 4,
      "last_reply_at": "2025-07-07T11:45:00Z"
    },
    {
      "id": "msg-004",
      "conversation_id": "conv-001",
      "sender_id": "teacher-001",
      "content": "I love that idea! We could even have them present their meal plans to the class. Real-world application of percentages and budgeting.",
      "type": "text",
      "reply_to": "msg-003",
      "created_at": "2025-07-07T11:38:00Z"
    },
    {
      "id": "msg-005",
      "conversation_id": "conv-001",
      "sender_id": "teacher-002",
      "content": "Exactly what I was thinking. Here is my location for our Wednesday meeting.",
      "type": "text",
      "created_at": "2025-07-08T11:30:00Z"
    },
    {
      "id": "msg-006",
      "conversation_id": "conv-001",
      "sender_id": "teacher-002",
      "content": null,
      "type": "location",
      "metadata": {
        "latitude": 40.7128,
        "longitude": -74.006,
        "place_name": "Room 204, PS 113"
      },
      "created_at": "2025-07-08T11:30:15Z",
      "reactions": [
        {
          "emoji": "😍",
          "count": 5
        }
      ]
    },
    {
      "id": "msg-007",
      "conversation_id": "conv-001",
      "sender_id": "teacher-001",
      "content": "See you there! I'll bring some sample meal planning worksheets I've used before.",
      "type": "text",
      "created_at": "2025-07-08T11:32:00Z"
    },
    {
      "id": "msg-020",
      "conversation_id": "conv-002",
      "sender_id": "teacher-003",
      "content": "Jean! Did you see the email about the new curriculum guidelines?",
      "type": "text",
      "created_at": "2025-07-07T09:00:00Z"
    },
    {
      "id": "msg-021",
      "conversation_id": "conv-002",
      "sender_id": "teacher-001",
      "content": "Just read it. I'm concerned about the timeline they're giving us to implement changes.",
      "type": "text",
      "created_at": "2025-07-07T09:15:00Z"
    },
    {
      "id": "msg-022",
      "conversation_id": "conv-002",
      "sender_id": "teacher-003",
      "content": "Same. Want to draft a response together? I think if we come from multiple departments it'll carry more weight.",
      "type": "text",
      "created_at": "2025-07-07T09:20:00Z"
    },
    {
      "id": "msg-023",
      "conversation_id": "conv-002",
      "sender_id": "teacher-001",
      "content": "Great idea. Let's loop in Mary too - she mentioned similar concerns at lunch yesterday.",
      "type": "text",
      "created_at": "2025-07-07T09:25:00Z"
    },
    {
      "id": "msg-030",
      "conversation_id": "conv-003",
      "sender_id": "teacher-004",
      "content": "Thanks so much for sharing your classroom management strategies last week. I tried the 'choice board' approach and it worked wonders!",
      "type": "text",
      "created_at": "2025-07-06T14:00:00Z"
    },
    {
      "id": "msg-031",
      "conversation_id": "conv-003",
      "sender_id": "teacher-001",
      "content": "So glad to hear that! Which options did your students gravitate toward?",
      "type": "text",
      "created_at": "2025-07-06T14:30:00Z"
    },
    {
      "id": "msg-032",
      "conversation_id": "conv-003",
      "sender_id": "teacher-004",
      "content": "Mostly the creative writing prompts and the partner discussion option. They really responded to having autonomy.",
      "type": "text",
      "created_at": "2025-07-06T14:45:00Z"
    },
    {
      "id": "msg-040",
      "conversation_id": "conv-004",
      "sender_id": "teacher-006",
      "content": "Hey Shem, I have a student who's really struggling with word problems. Any strategies you'd recommend?",
      "type": "text",
      "created_at": "2025-07-08T08:30:00Z"
    },
    {
      "id": "msg-041",
      "conversation_id": "conv-004",
      "sender_id": "teacher-002",
      "content": "Absolutely! I use a 'CUBES' strategy - Circle numbers, Underline the question, Box key words, Evaluate steps, Solve and check.",
      "type": "text",
      "created_at": "2025-07-08T08:45:00Z"
    },
    {
      "id": "msg-042",
      "conversation_id": "conv-004",
      "sender_id": "teacher-002",
      "content": null,
      "type": "voice",
      "metadata": {
        "duration_seconds": 45,
        "transcript": "I also find it helpful to have students draw a picture or diagram of the problem first. For students with IEPs, I often provide a graphic organizer that breaks down each step..."
      },
      "created_at": "2025-07-08T08:47:00Z"
    },
    {
      "id": "msg-043",
      "conversation_id": "conv-004",
      "sender_id": "teacher-006",
      "content": "This is so helpful! Would you mind if I observed your class sometime?",
      "type": "text",
      "created_at": "2025-07-08T09:00:00Z"
    },
    {
      "id": "msg-044",
      "conversation_id": "conv-004",
      "sender_id": "teacher-002",
      "content": "Of course! I'm doing a word problem unit next week. Come by Tuesday 3rd period.",
      "type": "text",
      "created_at": "2025-07-08T09:15:00Z"
    },
    {
      "id": "msg-100",
      "conversation_id": "conv-006",
      "sender_id": "teacher-001",
      "content": "Team meeting reminder: Tomorrow at 3:15 in my room. We need to discuss the parent-teacher conference schedule.",
      "type": "text",
      "created_at": "2025-07-07T16:00:00Z"
    },
    {
      "id": "msg-101",
      "conversation_id": "conv-006",
      "sender_id": "teacher-002",
      "content": "I'll be there! Should we also talk about the field trip logistics?",
      "type": "text",
      "created_at": "2025-07-07T16:15:00Z"
    },
    {
      "id": "msg-102",
      "conversation_id": "conv-006",
      "sender_id": "teacher-010",
      "content": "Good idea. I have the permission slip template ready to share.",
      "type": "text",
      "created_at": "2025-07-07T16:30:00Z"
    },
    {
      "id": "msg-103",
      "conversation_id": "conv-006",
      "sender_id": "teacher-013",
      "content": "Can we add student progress reports to the agenda? I'm seeing some concerning patterns in a few students.",
      "type": "text",
      "created_at": "2025-07-07T17:00:00Z"
    },
    {
      "id": "msg-104",
      "conversation_id": "conv-006",
      "sender_id": "teacher-001",
      "content": "Absolutely. Updated agenda: 1) P-T conferences, 2) Field trip, 3) Student progress. See everyone tomorrow!",
      "type": "text",
      "created_at": "2025-07-08T08:00:00Z"
    },
    {
      "id": "msg-200",
      "conversation_id": "conv-007",
      "sender_id": "teacher-018",
      "content": "Has anyone tried the new Desmos activities for quadratics? My students loved them!",
      "type": "text",
      "created_at": "2025-07-07T10:00:00Z"
    },
    {
      "id": "msg-201",
      "conversation_id": "conv-007",
      "sender_id": "teacher-002",
      "content": "Yes! The marble slides activity is a game changer. Even my reluctant learners were engaged.",
      "type": "text",
      "created_at": "2025-07-07T10:30:00Z"
    },
    {
      "id": "msg-202",
      "conversation_id": "conv-007",
      "sender_id": "teacher-022",
      "content": "I'm putting together a PD session on Desmos for our school. Would either of you want to co-facilitate?",
      "type": "text",
      "created_at": "2025-07-07T11:00:00Z"
    },
    {
      "id": "msg-203",
      "conversation_id": "conv-007",
      "sender_id": "teacher-015",
      "content": "Count me in! I use it for physics simulations too - could show cross-curricular applications.",
      "type": "text",
      "created_at": "2025-07-07T14:00:00Z"
    },
    {
      "id": "msg-204",
      "conversation_id": "conv-007",
      "sender_id": "teacher-018",
      "content": "This is turning into something great! Let's set up a Jam session to plan it out?",
      "type": "text",
      "created_at": "2025-07-07T16:30:00Z"
    },
    {
      "id": "msg-300",
      "conversation_id": "conv-008",
      "sender_id": "teacher-007",
      "content": "Big news: Our robotics team made it to regionals! 🎉",
      "type": "text",
      "created_at": "2025-07-08T09:00:00Z"
    },
    {
      "id": "msg-301",
      "conversation_id": "conv-008",
      "sender_id": "teacher-025",
      "content": "Congratulations Amanda! That's incredible! What challenge are they competing in?",
      "type": "text",
      "created_at": "2025-07-08T09:15:00Z"
    },
    {
      "id": "msg-302",
      "conversation_id": "conv-008",
      "sender_id": "teacher-007",
      "content": "The sustainability challenge - they built a robot that sorts recyclables. The kids designed the whole sorting algorithm themselves.",
      "type": "text",
      "created_at": "2025-07-08T09:30:00Z"
    },
    {
      "id": "msg-303",
      "conversation_id": "conv-008",
      "sender_id": "teacher-009",
      "content": "That's amazing! Would love to have them present to my coding class. Great real-world application.",
      "type": "text",
      "created_at": "2025-07-08T09:45:00Z"
    },
    {
      "id": "msg-304",
      "conversation_id": "conv-008",
      "sender_id": "teacher-021",
      "content": "Carlos here - I could tie this into our environmental science unit! Cross-school collaboration?",
      "type": "text",
      "created_at": "2025-07-08T10:00:00Z"
    },
    {
      "id": "msg-305",
      "conversation_id": "conv-008",
      "sender_id": "teacher-007",
      "content": "Love it! Let's set something up. This is exactly why I love this community.",
      "type": "text",
      "created_at": "2025-07-08T10:45:00Z"
    },
    {
      "id": "msg-400",
      "conversation_id": "conv-009",
      "sender_id": "teacher-014",
      "content": "First year survival check-in: How's everyone holding up as we approach the end of the year?",
      "type": "text",
      "created_at": "2025-07-05T15:00:00Z"
    },
    {
      "id": "msg-401",
      "conversation_id": "conv-009",
      "sender_id": "teacher-008",
      "content": "Honestly? Exhausted but proud. My students have grown so much. Still struggling with work-life balance though.",
      "type": "text",
      "created_at": "2025-07-05T15:30:00Z"
    },
    {
      "id": "msg-402",
      "conversation_id": "conv-009",
      "sender_id": "teacher-016",
      "content": "That's so normal for year one. Remember: you can't pour from an empty cup. What's one thing you're doing for yourself this weekend?",
      "type": "text",
      "created_at": "2025-07-05T16:00:00Z"
    },
    {
      "id": "msg-403",
      "conversation_id": "conv-009",
      "sender_id": "teacher-006",
      "content": "Aisha's right. Self-care isn't selfish - it's necessary. I'm going to the botanical garden Saturday if anyone wants to join!",
      "type": "text",
      "created_at": "2025-07-05T16:30:00Z"
    },
    {
      "id": "msg-404",
      "conversation_id": "conv-009",
      "sender_id": "teacher-022",
      "content": "I'd love that! Count me in. Teacher meetups outside of school have been so helpful for my mental health.",
      "type": "text",
      "created_at": "2025-07-06T09:00:00Z"
    },
    {
      "id": "msg-500",
      "conversation_id": "conv-010",
      "sender_id": "teacher-002",
      "content": "Anyone up for trivia night next Friday? Found a place in the Village that does education-themed rounds 😂",
      "type": "text",
      "created_at": "2025-07-07T17:00:00Z"
    },
    {
      "id": "msg-501",
      "conversation_id": "conv-010",
      "sender_id": "teacher-004",
      "content": "Education-themed trivia?! I'm definitely in. We're going to crush the literary questions.",
      "type": "text",
      "created_at": "2025-07-07T17:15:00Z"
    },
    {
      "id": "msg-502",
      "conversation_id": "conv-010",
      "sender_id": "teacher-005",
      "content": "Count me in! I'll bring my A-game for any art history questions 🎨",
      "type": "text",
      "created_at": "2025-07-07T17:30:00Z"
    },
    {
      "id": "msg-503",
      "conversation_id": "conv-010",
      "sender_id": "teacher-001",
      "content": "This sounds like so much fun! I need a night out. What time?",
      "type": "text",
      "created_at": "2025-07-07T18:00:00Z"
    },
    {
      "id": "msg-110",
      "conversation_id": "conv-011",
      "sender_id": "teacher-013",
      "content": "Heads up — the copier on the 2nd floor is out of toner again. Front office has more.",
      "type": "text",
      "created_at": "2025-07-07T15:00:00Z"
    },
    {
      "id": "msg-111",
      "conversation_id": "conv-011",
      "sender_id": "teacher-016",
      "content": "Thank you for the warning! Also does anyone have a stapler I can borrow for 3rd period?",
      "type": "text",
      "created_at": "2025-07-07T15:10:00Z"
    },
    {
      "id": "msg-112",
      "conversation_id": "conv-011",
      "sender_id": "teacher-010",
      "content": "I've got one in my mailbox slot, help yourself!",
      "type": "text",
      "created_at": "2025-07-07T15:12:00Z"
    },
    {
      "id": "msg-113",
      "conversation_id": "conv-011",
      "sender_id": "teacher-024",
      "content": "Potluck signup sheet is on the staff room fridge — we're still short on desserts!",
      "type": "text",
      "created_at": "2025-07-08T09:00:00Z"
    },
    {
      "id": "msg-114",
      "conversation_id": "conv-011",
      "sender_id": "teacher-002",
      "content": "I'll bring brownies 🍫",
      "type": "text",
      "created_at": "2025-07-08T09:05:00Z"
    },
    {
      "id": "msg-115",
      "conversation_id": "conv-011",
      "sender_id": "teacher-001",
      "content": "Can't wait — see everyone at 3:15 for the PD session too.",
      "type": "text",
      "created_at": "2025-07-08T12:15:00Z"
    },
    {
      "id": "msg-600",
      "conversation_id": "conv-community-001",
      "sender_id": "teacher-013",
      "content": "Excited to announce our summer book study! We'll be reading 'We Want to Do More Than Survive' by Bettina Love. First discussion July 20th.",
      "type": "text",
      "created_at": "2025-07-08T10:00:00Z"
    },
    {
      "id": "msg-601",
      "conversation_id": "conv-community-001",
      "sender_id": "teacher-016",
      "content": "Such an important book! I'll be there. Will there be virtual options for those traveling?",
      "type": "text",
      "created_at": "2025-07-08T10:30:00Z"
    },
    {
      "id": "msg-602",
      "conversation_id": "conv-community-001",
      "sender_id": "teacher-013",
      "content": "Yes! We'll have a hybrid option. I'll share the Zoom link closer to the date.",
      "type": "text",
      "created_at": "2025-07-08T11:00:00Z"
    },
    {
      "id": "msg-603",
      "conversation_id": "conv-community-001",
      "sender_id": "teacher-022",
      "content": "This community keeps me grounded. Thank you for organizing this, Marcus. 🙏🏾",
      "type": "text",
      "created_at": "2025-07-08T14:00:00Z"
    },
    {
      "id": "msg-700",
      "conversation_id": "conv-community-002",
      "sender_id": "teacher-001",
      "content": "Reminder: Staff meeting moved to Thursday this week due to PD on Wednesday.",
      "type": "text",
      "created_at": "2025-07-08T08:00:00Z"
    },
    {
      "id": "msg-701",
      "conversation_id": "conv-community-002",
      "sender_id": "teacher-002",
      "content": "Thanks for the heads up! Will the agenda be shared beforehand?",
      "type": "text",
      "created_at": "2025-07-08T08:30:00Z"
    },
    {
      "id": "msg-702",
      "conversation_id": "conv-community-002",
      "sender_id": "teacher-001",
      "content": "Yes, I'll post it by end of day today. Main topics: budget updates and summer school planning.",
      "type": "text",
      "created_at": "2025-07-08T09:00:00Z"
    },
    {
      "id": "msg-800",
      "conversation_id": "conv-community-003",
      "sender_id": "teacher-004",
      "content": "Just finished Chapter 3 and I'm blown away by the research on the brain-culture connection. Who else is caught up?",
      "type": "text",
      "created_at": "2025-07-05T19:00:00Z"
    },
    {
      "id": "msg-801",
      "conversation_id": "conv-community-003",
      "sender_id": "teacher-020",
      "content": "Just started! Already highlighting everything. The section on 'cognitive load' is making me rethink my lesson structure.",
      "type": "text",
      "created_at": "2025-07-05T19:30:00Z"
    },
    {
      "id": "msg-802",
      "conversation_id": "conv-community-003",
      "sender_id": "teacher-016",
      "content": "The 'ready for rigor' framework is gold. I'm creating a one-pager to share with my department.",
      "type": "text",
      "created_at": "2025-07-05T20:00:00Z"
    },
    {
      "id": "msg-900",
      "conversation_id": "conv-community-004",
      "sender_id": "teacher-009",
      "content": "Just uploaded my full coding curriculum for middle school - 12 weeks of lessons, all free to use and modify! Link in the resources folder.",
      "type": "text",
      "created_at": "2025-07-08T10:00:00Z"
    },
    {
      "id": "msg-901",
      "conversation_id": "conv-community-004",
      "sender_id": "teacher-007",
      "content": "Kai, you're amazing! I've been looking for something exactly like this. Can't wait to adapt it for my robotics kids.",
      "type": "text",
      "created_at": "2025-07-08T10:30:00Z"
    },
    {
      "id": "msg-902",
      "conversation_id": "conv-community-004",
      "sender_id": "teacher-003",
      "content": "This is why I love Lime. Teachers helping teachers. ❤️",
      "type": "text",
      "created_at": "2025-07-08T11:15:00Z"
    },
    {
      "id": "msg-1000",
      "conversation_id": "conv-community-005",
      "sender_id": "teacher-025",
      "content": "Who's going to the Maker Faire this weekend? Would be great to connect in person!",
      "type": "text",
      "created_at": "2025-07-07T14:00:00Z"
    },
    {
      "id": "msg-1001",
      "conversation_id": "conv-community-005",
      "sender_id": "teacher-015",
      "content": "I'll be there with some of my physics students! We're presenting our Rube Goldberg machine.",
      "type": "text",
      "created_at": "2025-07-07T14:30:00Z"
    },
    {
      "id": "msg-1002",
      "conversation_id": "conv-community-005",
      "sender_id": "teacher-017",
      "content": "Chemistry demo booth here! Come see some controlled explosions 💥 (all safety-approved, I promise)",
      "type": "text",
      "created_at": "2025-07-07T15:00:00Z"
    },
    {
      "id": "msg-1003",
      "conversation_id": "conv-community-005",
      "sender_id": "teacher-025",
      "content": "Let's do a Lime meetup at 2pm by the main stage? We can all connect and maybe get a group photo.",
      "type": "text",
      "created_at": "2025-07-07T16:45:00Z"
    },
    {
      "id": "msg-1004",
      "conversation_id": "conv-001",
      "sender_id": "teacher-002",
      "content": "Perfect, I'll draft a rubric for the budget component this week.",
      "type": "text",
      "reply_to": "msg-003",
      "created_at": "2025-07-07T11:41:00Z"
    },
    {
      "id": "msg-1005",
      "conversation_id": "conv-001",
      "sender_id": "teacher-001",
      "content": "Sounds great — let's sync on it Wednesday.",
      "type": "text",
      "reply_to": "msg-003",
      "created_at": "2025-07-07T11:45:00Z"
    }
  ]
};
