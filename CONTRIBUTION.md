# Contributing Guidelines

**IMPORTANT: All teeam members MUST follow this structure, to avoid repetitions and code duplicates. No exceptions**

## Project Structure - LETS STICK TO THIS

DSA-ASSIGNMENT2_2025/
├── docker/
│   └── mongo-init.js          ← ONLY database init script
│
├── docs/
│   └── documentation.txt
│
├── infrastructure/
│   ├── kafka/
│   │   ├── create-topics.sh
│   │   └── kafka.txt
│   │
│   └── nginx/
│       └── nginx.conf
│
├── scripts/
│   ├── health-check.sh
│   └── (other scripts)
│
├── services/
│   ├── admin-service/
│   ├── cli-client/
│   ├── notification-service/
│   ├── passenger-service/
│   ├── payment-service/
│   ├── ticketing-service/
│   ├── transport-service/
│   └── validation-service/
│
├── .env.example
├── .gitignore
├── docker-compose.yml
└── README.md


## Service Structure - MANDATORY

**Every service MUST have EXACTLY these 5 files:**

service-name/
├── Ballerina.toml
├── Config.toml
├── Dependencies.toml
├── Dockerfile
└── main.bal          ← NOT service.bal!


## Rules

1. **DO NOT** create duplicate files
2. **DO NOT** create nested `infrastructure/infrastructure/`
3. **DO NOT** create database init scripts anywhere except `docker/mongo-init.js`
4. **ALWAYS** name service files `main.bal` (not `service.bal`)
5. **ALWAYS** put Kafka scripts in `infrastructure/kafka/`
6. **NEVER** put `.gitignore` or `.devcontainer.json` inside service folders

## Before Committing

Run this checklist:

- [ ] No duplicate files
- [ ] Service has exactly 5 files
- [ ] Using `main.bal` not `service.bal`
- [ ] No files outside the approved structure
- [ ] Ran `git status` to check what you're committing
