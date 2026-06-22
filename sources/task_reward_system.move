/// Task Management & Reward System on Sui blockchain.
///
/// This module implements a decentralized task management system where:
/// - Anyone can create tasks with reward points
/// - Task creators can assign tasks to users
/// - Assigned users can complete tasks to earn points and level up
/// - A shared registry keeps track of all tasks on-chain
module task_reward_system::task_reward_system {

    use std::string::{Self, String};
    use std::option::{Self, Option};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::table::{Self, Table};

    // ===== Error Codes =====

    /// Caller is not the task creator (abort code 1)
    const E_NOT_CREATOR: u64 = 1;
    /// Caller is not the task assignee (abort code 2)
    const E_NOT_ASSIGNEE: u64 = 2;
    /// Task is already completed (abort code 3)
    const E_TASK_COMPLETED: u64 = 3;
    /// Reward points must be greater than zero (abort code 4)
    const E_INVALID_REWARD: u64 = 4;
    /// Task has no assignee yet (abort code 6)
    const E_NO_ASSIGNEE: u64 = 6;

    // ===== Status Constants =====

    /// Task is pending / not yet completed
    const STATUS_PENDING: u8 = 0;
    /// Task has been completed
    const STATUS_COMPLETED: u8 = 1;

    // ===== Level Thresholds =====

    const LEVEL_2_THRESHOLD: u64 = 100;
    const LEVEL_3_THRESHOLD: u64 = 200;
    const LEVEL_4_THRESHOLD: u64 = 300;
    const LEVEL_5_THRESHOLD: u64 = 500;

    // ===== Structs =====

    /// Represents a single task in the system.
    /// Tasks are stored inside the shared Registry table.
    public struct Task has key, store {
        id: UID,
        /// Human-readable task title
        title: String,
        /// Detailed description of what needs to be done
        description: String,
        /// Points awarded to the assignee upon completion
        reward_points: u64,
        /// Current status: STATUS_PENDING or STATUS_COMPLETED
        status: u8,
        /// Address of the user who created the task
        creator: address,
        /// Optional address of the user assigned to complete the task
        assignee: Option<address>,
    }

    /// A user's profile tracking their progress and achievements.
    public struct UserProfile has key, store {
        id: UID,
        /// The address that owns this profile
        owner: address,
        /// Total number of tasks this user has completed
        total_tasks_completed: u64,
        /// Cumulative points earned from completed tasks
        total_points_earned: u64,
        /// Current level (1-5) derived from total_points_earned
        level: u8,
    }

    /// Shared registry that stores all tasks and a global counter.
    /// Being a shared object, any user can interact with it.
    public struct Registry has key {
        id: UID,
        /// Maps task_counter index -> Task object
        all_tasks: Table<u64, Task>,
        /// Monotonically increasing counter used as task IDs in the table
        task_counter: u64,
    }

    // ===== Events =====

    /// Emitted when a new task is created
    public struct TaskCreated has copy, drop {
        task_id: address,
        creator: address,
        reward_points: u64,
    }

    /// Emitted when a task is assigned to a user
    public struct TaskAssigned has copy, drop {
        task_id: address,
        assignee: address,
    }

    /// Emitted when a task is completed by the assignee
    public struct TaskCompleted has copy, drop {
        task_id: address,
        user: address,
        reward_points: u64,
        new_level: u8,
    }

    // ===== Initialization =====

    /// Called once at publish time — creates and shares the global Registry.
    fun init(ctx: &mut TxContext) {
        initialize(ctx);
    }

    /// Public wrapper around init so tests can call it directly.
    public fun initialize(ctx: &mut TxContext) {
        let registry = Registry {
            id: object::new(ctx),
            all_tasks: table::new(ctx),
            task_counter: 0,
        };
        transfer::share_object(registry);
    }

    // ===== Profile Functions =====

    /// Creates a new UserProfile for the transaction sender.
    public fun create_profile(ctx: &mut TxContext) {
        let owner = tx_context::sender(ctx);
        let profile = UserProfile {
            id: object::new(ctx),
            owner,
            total_tasks_completed: 0,
            total_points_earned: 0,
            level: 1,
        };
        transfer::transfer(profile, owner);
    }

    // ===== Task Functions =====

    /// Creates a new task and stores it in the shared Registry.
    ///
    /// - `title`         : UTF-8 bytes for the task title
    /// - `description`   : UTF-8 bytes for the task description
    /// - `reward_points` : Points to award upon completion (must be > 0)
    public fun create_task(
        registry: &mut Registry,
        title: vector<u8>,
        description: vector<u8>,
        reward_points: u64,
        ctx: &mut TxContext,
    ) {
        assert!(reward_points > 0, E_INVALID_REWARD);

        let creator = tx_context::sender(ctx);
        let task_id_obj = object::new(ctx);
        let task_addr = object::uid_to_address(&task_id_obj);

        let task = Task {
            id: task_id_obj,
            title: string::utf8(title),
            description: string::utf8(description),
            reward_points,
            status: STATUS_PENDING,
            creator,
            assignee: option::none(),
        };

        let index = registry.task_counter;
        table::add(&mut registry.all_tasks, index, task);
        registry.task_counter = index + 1;

        event::emit(TaskCreated {
            task_id: task_addr,
            creator,
            reward_points,
        });
    }

    /// Assigns a task to a user. Only the task creator may call this.
    /// Cannot assign an already-completed task.
    public fun assign_task(
        registry: &mut Registry,
        task_index: u64,
        user_address: address,
        ctx: &mut TxContext,
    ) {
        let caller = tx_context::sender(ctx);
        let task = table::borrow_mut(&mut registry.all_tasks, task_index);

        assert!(task.creator == caller, E_NOT_CREATOR);
        assert!(task.status != STATUS_COMPLETED, E_TASK_COMPLETED);

        let task_addr = object::uid_to_address(&task.id);
        task.assignee = option::some(user_address);

        event::emit(TaskAssigned {
            task_id: task_addr,
            assignee: user_address,
        });
    }

    /// Marks a task as completed. Only the assigned user may call this.
    /// Updates the user profile and recalculates their level.
    public fun complete_task(
        registry: &mut Registry,
        task_index: u64,
        user_profile: &mut UserProfile,
        ctx: &mut TxContext,
    ) {
        let caller = tx_context::sender(ctx);
        let task = table::borrow_mut(&mut registry.all_tasks, task_index);

        assert!(option::is_some(&task.assignee), E_NO_ASSIGNEE);
        assert!(*option::borrow(&task.assignee) == caller, E_NOT_ASSIGNEE);
        assert!(task.status != STATUS_COMPLETED, E_TASK_COMPLETED);

        let reward = task.reward_points;
        let task_addr = object::uid_to_address(&task.id);

        task.status = STATUS_COMPLETED;

        user_profile.total_tasks_completed = user_profile.total_tasks_completed + 1;
        user_profile.total_points_earned = user_profile.total_points_earned + reward;

        level_up(user_profile);

        event::emit(TaskCompleted {
            task_id: task_addr,
            user: caller,
            reward_points: reward,
            new_level: user_profile.level,
        });
    }

    // ===== Internal Helpers =====

    /// Recalculates and updates the user's level based on total points earned.
    ///
    /// Level thresholds:
    ///   0 –  99 points  →  Level 1
    /// 100 – 199 points  →  Level 2
    /// 200 – 299 points  →  Level 3
    /// 300 – 499 points  →  Level 4
    /// 500+      points  →  Level 5
    fun level_up(profile: &mut UserProfile) {
        let points = profile.total_points_earned;
        profile.level = if (points >= LEVEL_5_THRESHOLD) {
            5
        } else if (points >= LEVEL_4_THRESHOLD) {
            4
        } else if (points >= LEVEL_3_THRESHOLD) {
            3
        } else if (points >= LEVEL_2_THRESHOLD) {
            2
        } else {
            1
        };
    }

    // ===== Getter Functions – Task =====

    public fun get_task_title(registry: &Registry, task_index: u64): String {
        table::borrow(&registry.all_tasks, task_index).title
    }

    public fun get_task_description(registry: &Registry, task_index: u64): String {
        table::borrow(&registry.all_tasks, task_index).description
    }

    public fun get_task_reward(registry: &Registry, task_index: u64): u64 {
        table::borrow(&registry.all_tasks, task_index).reward_points
    }

    public fun get_task_status(registry: &Registry, task_index: u64): u8 {
        table::borrow(&registry.all_tasks, task_index).status
    }

    public fun get_task_creator(registry: &Registry, task_index: u64): address {
        table::borrow(&registry.all_tasks, task_index).creator
    }

    public fun get_task_assignee(registry: &Registry, task_index: u64): Option<address> {
        table::borrow(&registry.all_tasks, task_index).assignee
    }

    // ===== Getter Functions – UserProfile =====

    public fun get_user_level(profile: &UserProfile): u8 {
        profile.level
    }

    public fun get_user_points(profile: &UserProfile): u64 {
        profile.total_points_earned
    }

    public fun get_completed_tasks(profile: &UserProfile): u64 {
        profile.total_tasks_completed
    }

    public fun get_profile_owner(profile: &UserProfile): address {
        profile.owner
    }

    public fun get_task_counter(registry: &Registry): u64 {
        registry.task_counter
    }

    // ===== Status Helpers =====

    public fun status_pending(): u8 { STATUS_PENDING }
    public fun status_completed(): u8 { STATUS_COMPLETED }
}
