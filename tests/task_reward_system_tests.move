/// Comprehensive tests for the Task Management & Reward System.
///
/// Test coverage:
///   SUCCESS CASES
///     ✓ create_profile
///     ✓ create_task
///     ✓ assign_task
///     ✓ complete_task
///     ✓ level up at each threshold
///     ✓ multiple tasks / cumulative points
///     ✓ getter functions
///
///   FAILURE CASES
///     ✓ non-creator assigns task     → abort code 1 (E_NOT_CREATOR)
///     ✓ non-assignee completes task  → abort code 2 (E_NOT_ASSIGNEE)
///     ✓ complete task twice          → abort code 3 (E_TASK_COMPLETED)
///     ✓ assign completed task        → abort code 3 (E_TASK_COMPLETED)
///     ✓ zero reward points           → abort code 4 (E_INVALID_REWARD)
///     ✓ complete with no assignee    → abort code 6 (E_NO_ASSIGNEE)
#[test_only]
module task_reward_system::task_reward_system_tests {

    use std::string;
    use std::option;
    use sui::test_scenario::{Self as ts, Scenario};
    use task_reward_system::task_reward_system::{
        Self,
        Registry,
        UserProfile,
    };

    // ── Helpers ──────────────────────────────────────────────────────────────

    /// Standard test addresses
    const ADMIN:    address = @0xA;
    const CREATOR:  address = @0xB;
    const ASSIGNEE: address = @0xC;
    const STRANGER: address = @0xD;

    /// Shorthand task parameters
    const TITLE:       vector<u8> = b"Fix Bug #42";
    const DESCRIPTION: vector<u8> = b"Reproduce and fix the null-pointer crash in login flow.";
    const REWARD:      u64 = 50;

    /// Initialise the module and return the scenario (caller = ADMIN).
    fun setup(): Scenario {
        let mut scenario = ts::begin(ADMIN);
        {
            task_reward_system::initialize(ts::ctx(&mut scenario));
        };
        scenario
    }

    /// Helper: create a profile for `who` inside `scenario`.
    fun create_profile_for(scenario: &mut Scenario, who: address) {
        ts::next_tx(scenario, who);
        task_reward_system::create_profile(ts::ctx(scenario));
    }

    /// Helper: create a task as CREATOR.
    fun create_default_task(scenario: &mut Scenario) {
        ts::next_tx(scenario, CREATOR);
        let mut registry = ts::take_shared<Registry>(scenario);
        task_reward_system::create_task(
            &mut registry,
            TITLE,
            DESCRIPTION,
            REWARD,
            ts::ctx(scenario),
        );
        ts::return_shared(registry);
    }

    /// Helper: assign task at `index` to ASSIGNEE (called by CREATOR).
    fun assign_default_task(scenario: &mut Scenario, index: u64) {
        ts::next_tx(scenario, CREATOR);
        let mut registry = ts::take_shared<Registry>(scenario);
        task_reward_system::assign_task(
            &mut registry,
            index,
            ASSIGNEE,
            ts::ctx(scenario),
        );
        ts::return_shared(registry);
    }

    // =========================================================================
    //  SUCCESS CASES
    // =========================================================================

    #[test]
    fun test_create_profile_success() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);

        ts::next_tx(&mut scenario, ASSIGNEE);
        let profile = ts::take_from_sender<UserProfile>(&scenario);

        assert!(task_reward_system::get_profile_owner(&profile) == ASSIGNEE, 0);
        assert!(task_reward_system::get_user_level(&profile) == 1, 1);
        assert!(task_reward_system::get_user_points(&profile) == 0, 2);
        assert!(task_reward_system::get_completed_tasks(&profile) == 0, 3);

        ts::return_to_sender(&scenario, profile);
        ts::end(scenario);
    }

    #[test]
    fun test_create_task_success() {
        let mut scenario = setup();
        create_default_task(&mut scenario);

        ts::next_tx(&mut scenario, ADMIN);
        let registry = ts::take_shared<Registry>(&scenario);

        assert!(task_reward_system::get_task_counter(&registry) == 1, 0);
        assert!(task_reward_system::get_task_title(&registry, 0) == string::utf8(TITLE), 1);
        assert!(task_reward_system::get_task_description(&registry, 0) == string::utf8(DESCRIPTION), 2);
        assert!(task_reward_system::get_task_reward(&registry, 0) == REWARD, 3);
        assert!(task_reward_system::get_task_status(&registry, 0) == task_reward_system::status_pending(), 4);
        assert!(task_reward_system::get_task_creator(&registry, 0) == CREATOR, 5);
        assert!(option::is_none(&task_reward_system::get_task_assignee(&registry, 0)), 6);

        ts::return_shared(registry);
        ts::end(scenario);
    }

    #[test]
    fun test_assign_task_success() {
        let mut scenario = setup();
        create_default_task(&mut scenario);
        assign_default_task(&mut scenario, 0);

        ts::next_tx(&mut scenario, ADMIN);
        let registry = ts::take_shared<Registry>(&scenario);

        let assignee_opt = task_reward_system::get_task_assignee(&registry, 0);
        assert!(option::is_some(&assignee_opt), 0);
        assert!(*option::borrow(&assignee_opt) == ASSIGNEE, 1);

        ts::return_shared(registry);
        ts::end(scenario);
    }

    #[test]
    fun test_complete_task_success() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);
        create_default_task(&mut scenario);
        assign_default_task(&mut scenario, 0);

        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);

            task_reward_system::complete_task(
                &mut registry,
                0,
                &mut profile,
                ts::ctx(&mut scenario),
            );

            assert!(task_reward_system::get_task_status(&registry, 0) == task_reward_system::status_completed(), 0);
            assert!(task_reward_system::get_completed_tasks(&profile) == 1, 1);
            assert!(task_reward_system::get_user_points(&profile) == REWARD, 2);
            assert!(task_reward_system::get_user_level(&profile) == 1, 3);

            ts::return_shared(registry);
            ts::return_to_sender(&scenario, profile);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_level_up_to_level_2() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);

        let mut i = 0u64;
        while (i < 2) {
            ts::next_tx(&mut scenario, CREATOR);
            {
                let mut registry = ts::take_shared<Registry>(&scenario);
                task_reward_system::create_task(&mut registry, b"Task", b"Desc", 60, ts::ctx(&mut scenario));
                ts::return_shared(registry);
            };
            ts::next_tx(&mut scenario, CREATOR);
            {
                let mut registry = ts::take_shared<Registry>(&scenario);
                task_reward_system::assign_task(&mut registry, i, ASSIGNEE, ts::ctx(&mut scenario));
                ts::return_shared(registry);
            };
            ts::next_tx(&mut scenario, ASSIGNEE);
            {
                let mut registry = ts::take_shared<Registry>(&scenario);
                let mut profile = ts::take_from_sender<UserProfile>(&scenario);
                task_reward_system::complete_task(&mut registry, i, &mut profile, ts::ctx(&mut scenario));
                ts::return_shared(registry);
                ts::return_to_sender(&scenario, profile);
            };
            i = i + 1;
        };

        ts::next_tx(&mut scenario, ASSIGNEE);
        let profile = ts::take_from_sender<UserProfile>(&scenario);
        assert!(task_reward_system::get_user_points(&profile) == 120, 0);
        assert!(task_reward_system::get_user_level(&profile) == 2, 1);
        ts::return_to_sender(&scenario, profile);
        ts::end(scenario);
    }

    #[test]
    fun test_level_up_to_level_4() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            task_reward_system::create_task(&mut registry, b"Big Task", b"Big reward", 300, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            task_reward_system::assign_task(&mut registry, 0, ASSIGNEE, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);
            task_reward_system::complete_task(&mut registry, 0, &mut profile, ts::ctx(&mut scenario));
            assert!(task_reward_system::get_user_level(&profile) == 4, 0);
            ts::return_shared(registry);
            ts::return_to_sender(&scenario, profile);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_level_up_to_level_5() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);

        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            task_reward_system::create_task(&mut registry, b"Epic Task", b"Epic reward", 500, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, CREATOR);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            task_reward_system::assign_task(&mut registry, 0, ASSIGNEE, ts::ctx(&mut scenario));
            ts::return_shared(registry);
        };
        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);
            task_reward_system::complete_task(&mut registry, 0, &mut profile, ts::ctx(&mut scenario));
            assert!(task_reward_system::get_user_level(&profile) == 5, 0);
            assert!(task_reward_system::get_user_points(&profile) == 500, 1);
            ts::return_shared(registry);
            ts::return_to_sender(&scenario, profile);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_multiple_tasks_cumulative_points() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);

        ts::next_tx(&mut scenario, CREATOR);
        { let mut reg = ts::take_shared<Registry>(&scenario); task_reward_system::create_task(&mut reg, b"T0", b"D", 80, ts::ctx(&mut scenario)); ts::return_shared(reg); };
        ts::next_tx(&mut scenario, CREATOR);
        { let mut reg = ts::take_shared<Registry>(&scenario); task_reward_system::assign_task(&mut reg, 0, ASSIGNEE, ts::ctx(&mut scenario)); ts::return_shared(reg); };

        ts::next_tx(&mut scenario, CREATOR);
        { let mut reg = ts::take_shared<Registry>(&scenario); task_reward_system::create_task(&mut reg, b"T1", b"D", 150, ts::ctx(&mut scenario)); ts::return_shared(reg); };
        ts::next_tx(&mut scenario, CREATOR);
        { let mut reg = ts::take_shared<Registry>(&scenario); task_reward_system::assign_task(&mut reg, 1, ASSIGNEE, ts::ctx(&mut scenario)); ts::return_shared(reg); };

        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let mut reg = ts::take_shared<Registry>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);
            task_reward_system::complete_task(&mut reg, 0, &mut profile, ts::ctx(&mut scenario));
            assert!(task_reward_system::get_user_points(&profile) == 80, 0);
            assert!(task_reward_system::get_user_level(&profile) == 1, 1);
            ts::return_shared(reg);
            ts::return_to_sender(&scenario, profile);
        };

        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let mut reg = ts::take_shared<Registry>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);
            task_reward_system::complete_task(&mut reg, 1, &mut profile, ts::ctx(&mut scenario));
            assert!(task_reward_system::get_user_points(&profile) == 230, 2);
            assert!(task_reward_system::get_completed_tasks(&profile) == 2, 3);
            assert!(task_reward_system::get_user_level(&profile) == 3, 4);
            ts::return_shared(reg);
            ts::return_to_sender(&scenario, profile);
        };
        ts::end(scenario);
    }

    #[test]
    fun test_getters() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);
        create_default_task(&mut scenario);
        assign_default_task(&mut scenario, 0);

        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let registry = ts::take_shared<Registry>(&scenario);
            let profile = ts::take_from_sender<UserProfile>(&scenario);

            assert!(task_reward_system::get_task_title(&registry, 0) == string::utf8(TITLE), 0);
            assert!(task_reward_system::get_task_description(&registry, 0) == string::utf8(DESCRIPTION), 1);
            assert!(task_reward_system::get_task_reward(&registry, 0) == REWARD, 2);
            assert!(task_reward_system::get_task_status(&registry, 0) == task_reward_system::status_pending(), 3);
            assert!(task_reward_system::get_task_creator(&registry, 0) == CREATOR, 4);
            assert!(*option::borrow(&task_reward_system::get_task_assignee(&registry, 0)) == ASSIGNEE, 5);
            assert!(task_reward_system::get_user_level(&profile) == 1, 6);
            assert!(task_reward_system::get_user_points(&profile) == 0, 7);
            assert!(task_reward_system::get_completed_tasks(&profile) == 0, 8);
            assert!(task_reward_system::get_profile_owner(&profile) == ASSIGNEE, 9);
            assert!(task_reward_system::get_task_counter(&registry) == 1, 10);

            ts::return_shared(registry);
            ts::return_to_sender(&scenario, profile);
        };
        ts::end(scenario);
    }

    // =========================================================================
    //  FAILURE CASES
    // =========================================================================

    #[test]
    #[expected_failure(abort_code = 1)] // E_NOT_CREATOR
    fun test_non_creator_assign_task_fails() {
        let mut scenario = setup();
        create_default_task(&mut scenario);

        ts::next_tx(&mut scenario, STRANGER);
        let mut registry = ts::take_shared<Registry>(&scenario);
        task_reward_system::assign_task(&mut registry, 0, ASSIGNEE, ts::ctx(&mut scenario));
        ts::return_shared(registry);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 2)] // E_NOT_ASSIGNEE
    fun test_non_assignee_complete_task_fails() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, STRANGER);
        create_default_task(&mut scenario);
        assign_default_task(&mut scenario, 0);

        ts::next_tx(&mut scenario, STRANGER);
        let mut registry = ts::take_shared<Registry>(&scenario);
        let mut profile = ts::take_from_sender<UserProfile>(&scenario);
        task_reward_system::complete_task(&mut registry, 0, &mut profile, ts::ctx(&mut scenario));
        ts::return_shared(registry);
        ts::return_to_sender(&scenario, profile);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)] // E_TASK_COMPLETED
    fun test_complete_task_twice_fails() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);
        create_default_task(&mut scenario);
        assign_default_task(&mut scenario, 0);

        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);
            task_reward_system::complete_task(&mut registry, 0, &mut profile, ts::ctx(&mut scenario));
            ts::return_shared(registry);
            ts::return_to_sender(&scenario, profile);
        };

        ts::next_tx(&mut scenario, ASSIGNEE);
        let mut registry = ts::take_shared<Registry>(&scenario);
        let mut profile = ts::take_from_sender<UserProfile>(&scenario);
        task_reward_system::complete_task(&mut registry, 0, &mut profile, ts::ctx(&mut scenario));
        ts::return_shared(registry);
        ts::return_to_sender(&scenario, profile);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 3)] // E_TASK_COMPLETED
    fun test_assign_completed_task_fails() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, ASSIGNEE);
        create_default_task(&mut scenario);
        assign_default_task(&mut scenario, 0);

        ts::next_tx(&mut scenario, ASSIGNEE);
        {
            let mut registry = ts::take_shared<Registry>(&scenario);
            let mut profile = ts::take_from_sender<UserProfile>(&scenario);
            task_reward_system::complete_task(&mut registry, 0, &mut profile, ts::ctx(&mut scenario));
            ts::return_shared(registry);
            ts::return_to_sender(&scenario, profile);
        };

        ts::next_tx(&mut scenario, CREATOR);
        let mut registry = ts::take_shared<Registry>(&scenario);
        task_reward_system::assign_task(&mut registry, 0, STRANGER, ts::ctx(&mut scenario));
        ts::return_shared(registry);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 4)] // E_INVALID_REWARD
    fun test_zero_reward_points_fails() {
        let mut scenario = setup();

        ts::next_tx(&mut scenario, CREATOR);
        let mut registry = ts::take_shared<Registry>(&scenario);
        task_reward_system::create_task(&mut registry, b"Bad Task", b"No reward", 0, ts::ctx(&mut scenario));
        ts::return_shared(registry);
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 6)] // E_NO_ASSIGNEE
    fun test_complete_task_without_assignee_fails() {
        let mut scenario = setup();
        create_profile_for(&mut scenario, CREATOR);
        create_default_task(&mut scenario);

        ts::next_tx(&mut scenario, CREATOR);
        let mut registry = ts::take_shared<Registry>(&scenario);
        let mut profile = ts::take_from_sender<UserProfile>(&scenario);
        task_reward_system::complete_task(&mut registry, 0, &mut profile, ts::ctx(&mut scenario));
        ts::return_shared(registry);
        ts::return_to_sender(&scenario, profile);
        ts::end(scenario);
    }
}
