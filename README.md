# Task Management & Reward System on Sui

A fully decentralized task management and reward system built with Sui Move.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Project Structure](#project-structure)
4. [Installation & Prerequisites](#installation--prerequisites)
5. [Build](#build)
6. [Test](#test)
7. [Publish (Deploy)](#publish-deploy)
8. [CLI Usage Examples](#cli-usage-examples)
9. [Level System](#level-system)
10. [Error Codes](#error-codes)
11. [Events](#events)

---

## Overview

This module lets anyone on the Sui network:

- Create **tasks** with a title, description, and reward points
- **Assign** tasks to other users (creator-only)
- **Complete** tasks to earn points and automatically level up (assignee-only)
- Track progress via a persistent **UserProfile**

All tasks live inside a single **shared Registry** object so every address can read and interact with them.

---
## Deployed Testnet Instance

Package ID:
0x5183cd994d86693c9543d2086ed9a6df6d358eea0518194c87dfef44043f58d2

Registry ID:
0x2502a9803ff13ea8afa633fdcbf15de94f7e74e09947ef28ca25ef4df7c3c98c

Deployment Network:
Sui Testnet

Deployment Transaction:
59KvTZs4MtQBwKUi466KHJCbpEJyKbWWxBNzZoSaXELc


---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         Registry (shared)                   │
│   task_counter : u64                                        │
│   all_tasks    : Table<u64, Task>                           │
└─────────────────────────────────────────────────────────────┘
           │ contains
           ▼
┌──────────────────────┐         ┌──────────────────────┐
│        Task          │         │     UserProfile       │
│  id, title, desc     │         │  owner, level         │
│  reward_points       │         │  total_tasks_completed│
│  status (u8)         │         │  total_points_earned  │
│  creator, assignee   │         └──────────────────────┘
└──────────────────────┘
```

---

## Project Structure

```
task_reward_system/
│
├── Move.toml                          # Package manifest
│
├── sources/
│   └── task_reward_system.move        # Main module
│
├── tests/
│   └── task_reward_system_tests.move  # Comprehensive test suite
│
└── README.md                          # This file
```

---

## Installation & Prerequisites

### 1. Install Sui CLI

Follow the official guide:  
<https://docs.sui.io/guides/developer/getting-started/sui-install>

Verify:
```bash
sui --version
```

### 2. Set up a Testnet wallet (if not done already)

```bash
# Create a new keypair
sui client new-address ed25519

# Get testnet tokens from the faucet
sui client faucet
```

### 3. Point to Testnet

```bash
sui client new-env --alias testnet --rpc https://fullnode.testnet.sui.io:443
sui client switch --env testnet
```

---

## Build

```bash
cd task_reward_system
sui move build
```

Expected output:
```
UPDATING GIT DEPENDENCY https://github.com/MystenLabs/sui.git
INCLUDING DEPENDENCY Sui
INCLUDING DEPENDENCY MoveStdlib
BUILDING task_reward_system
```

---

## Test

```bash
sui move test
```

All 12 tests should pass:

```
Running Move unit tests
[ PASS    ] task_reward_system::task_reward_system_tests::test_assign_completed_task_fails
[ PASS    ] task_reward_system::task_reward_system_tests::test_assign_task_success
[ PASS    ] task_reward_system::task_reward_system_tests::test_complete_task_success
[ PASS    ] task_reward_system::task_reward_system_tests::test_complete_task_twice_fails
[ PASS    ] task_reward_system::task_reward_system_tests::test_complete_task_without_assignee_fails
[ PASS    ] task_reward_system::task_reward_system_tests::test_create_profile_success
[ PASS    ] task_reward_system::task_reward_system_tests::test_create_task_success
[ PASS    ] task_reward_system::task_reward_system_tests::test_getters
[ PASS    ] task_reward_system::task_reward_system_tests::test_level_up_to_level_2
[ PASS    ] task_reward_system::task_reward_system_tests::test_level_up_to_level_4
[ PASS    ] task_reward_system::task_reward_system_tests::test_level_up_to_level_5
[ PASS    ] task_reward_system::task_reward_system_tests::test_multiple_tasks_cumulative_points
[ PASS    ] task_reward_system::task_reward_system_tests::test_non_assignee_complete_task_fails
[ PASS    ] task_reward_system::task_reward_system_tests::test_non_creator_assign_task_fails
[ PASS    ] task_reward_system::task_reward_system_tests::test_zero_reward_points_fails
Test result: OK. Total tests: 15; passed: 15; failed: 0
```

Run a specific test:
```bash
sui move test test_complete_task_success
```

---

## Publish (Deploy)

### Publish to Testnet

```bash
sui client publish --gas-budget 100000000
```

After publishing, Sui prints the **Package ID** and the **Registry object ID** created by `init`.  
Save them — you will need them for all CLI calls:

```
----- Transaction Effects ----
Published Objects:
  ┌──
  │ PackageID: 0xPACKAGE_ID
  │ Version: 1
  └──
Created Objects:
  ┌──
  │ ID: 0xREGISTRY_ID        ← shared Registry
  │ Owner: Shared
  └──
```

Export as environment variables for convenience:
```bash
export PACKAGE=0x5183cd994d86693c9543d2086ed9a6df6d358eea0518194c87dfef44043f58d2

export REGISTRY=0x2502a9803ff13ea8afa633fdcbf15de94f7e74e09947ef28ca25ef4df7c3c98c
```

---

## CLI Usage Examples

### Create a Profile

```bash
sui client call \
  --package $PACKAGE \
  --module task_reward_system \
  --function create_profile \
  --gas-budget 10000000
```

Copy the resulting `UserProfile` object ID:
```bash
export PROFILE=0xYOUR_PROFILE_ID
```

---

### Create a Task

```bash
sui client call \
  --package $PACKAGE \
  --module task_reward_system \
  --function create_task \
  --args \
    $REGISTRY \
    '"Fix login bug"' \
    '"Reproduce and fix null-pointer crash in the login flow"' \
    50 \
  --gas-budget 10000000
```

The task is stored at index `task_counter - 1` in the registry.  
After the first call, the task index is `0`.

---

### Assign a Task

> Only the task creator can call this.

```bash
sui client call \
  --package $PACKAGE \
  --module task_reward_system \
  --function assign_task \
  --args \
    $REGISTRY \
    0 \
    0xASSIGNEE_ADDRESS \
  --gas-budget 10000000
```

Parameters:
- `$REGISTRY` — shared Registry object ID
- `0` — task index (u64)
- `0xASSIGNEE_ADDRESS` — the address to assign the task to

---

### Complete a Task

> Only the assigned user can call this.

```bash
sui client call \
  --package $PACKAGE \
  --module task_reward_system \
  --function complete_task \
  --args \
    $REGISTRY \
    0 \
    $PROFILE \
  --gas-budget 10000000
```

Parameters:
- `$REGISTRY` — shared Registry object ID
- `0` — task index (u64)
- `$PROFILE` — the caller's UserProfile object ID

---

### Read Task Info (off-chain query)

```bash
# Read the full registry object
sui client object $REGISTRY --json

# Read a specific profile
sui client object $PROFILE --json
```

---

## Level System

| Total Points Earned | Level |
|---------------------|-------|
| 0 – 99              | 1     |
| 100 – 199           | 2     |
| 200 – 299           | 3     |
| 300 – 499           | 4     |
| 500+                | 5     |

Level is recalculated automatically every time `complete_task` is called.

---

## Error Codes

| Constant              | Code | Meaning                                    |
|-----------------------|------|--------------------------------------------|
| `E_NOT_CREATOR`       | 1    | Caller is not the task creator             |
| `E_NOT_ASSIGNEE`      | 2    | Caller is not the task's assignee          |
| `E_TASK_COMPLETED`    | 3    | Task is already completed                  |
| `E_INVALID_REWARD`    | 4    | Reward points must be > 0                  |
| `E_PROFILE_NOT_FOUND` | 5    | Reserved for future profile-lookup helpers |
| `E_NO_ASSIGNEE`       | 6    | Task has no assignee yet                   |

---

## Events

### `TaskCreated`
```
task_id        : address   (UID of the Task object)
creator        : address
reward_points  : u64
```

### `TaskAssigned`
```
task_id   : address
assignee  : address
```

### `TaskCompleted`
```
task_id        : address
user           : address
reward_points  : u64
new_level      : u8
```

---

## License

MIT
