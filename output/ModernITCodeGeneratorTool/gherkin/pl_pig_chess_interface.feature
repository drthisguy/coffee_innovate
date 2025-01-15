Feature: Pl Pig Chess Interface
  As a system user
  I want to ensure all functionalities work as expected
  So that the system remains reliable and maintainable

  # Unit Test Scenarios
  Scenario: Test initialization of a new game with default parameters.
    Given the system is properly configured
    When executing unit test 'test_new_game_initialization'
    Then the test should pass successfully

  Scenario: Test initialization of a new game with custom parameters.
    Given the system is properly configured
    When executing unit test 'test_new_game_custom_parameters'
    Then the test should pass successfully

  Scenario: Test making a legal move.
    Given the system is properly configured
    When executing unit test 'test_do_move_legal'
    Then the test should pass successfully

  Scenario: Test attempting an illegal move.
    Given the system is properly configured
    When executing unit test 'test_do_move_illegal'
    Then the test should pass successfully

  Scenario: Test bot move execution.
    Given the system is properly configured
    When executing unit test 'test_do_bot_move'
    Then the test should pass successfully

  Scenario: Test bot level calculation.
    Given the system is properly configured
    When executing unit test 'test_get_bot_level'
    Then the test should pass successfully

  Scenario: Test finding the best move at different depths.
    Given the system is properly configured
    When executing unit test 'test_find_best_move'
    Then the test should pass successfully

  Scenario: Test minimax evaluation of a checkmate position.
    Given the system is properly configured
    When executing unit test 'test_minimax_checkmate'
    Then the test should pass successfully

  Scenario: Test position evaluation.
    Given the system is properly configured
    When executing unit test 'test_evaluate_position'
    Then the test should pass successfully

  Scenario: Test taking back a move.
    Given the system is properly configured
    When executing unit test 'test_takeback_move'
    Then the test should pass successfully

  Scenario: Test taking back two moves.
    Given the system is properly configured
    When executing unit test 'test_takeback_moves'
    Then the test should pass successfully

  Scenario: Test setting white's level.
    Given the system is properly configured
    When executing unit test 'test_set_white_level'
    Then the test should pass successfully

  Scenario: Test setting black's level.
    Given the system is properly configured
    When executing unit test 'test_set_black_level'
    Then the test should pass successfully

  Scenario: Test the engine on specific positions.
    Given the system is properly configured
    When executing unit test 'test_position'
    Then the test should pass successfully

  Scenario: Test running a suite of test positions.
    Given the system is properly configured
    When executing unit test 'test_run_test_suite'
    Then the test should pass successfully

  # Functional Test Scenarios
  Scenario: New game and bot play
    Given the system is in a production-like environment
    When performing functional test 'test_new_game_and_bot_play'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Human vs bot game
    Given the system is in a production-like environment
    When performing functional test 'test_human_vs_bot_game'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Invalid move
    Given the system is in a production-like environment
    When performing functional test 'test_invalid_move'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Valid move
    Given the system is in a production-like environment
    When performing functional test 'test_valid_move'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: New game reset
    Given the system is in a production-like environment
    When performing functional test 'test_new_game_reset'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Move on finished game
    Given the system is in a production-like environment
    When performing functional test 'test_move_on_finished_game'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Custom starting position
    Given the system is in a production-like environment
    When performing functional test 'test_custom_starting_position'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Evaluation speed
    Given the system is in a production-like environment
    When performing functional test 'test_evaluation_speed'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Takeback move
    Given the system is in a production-like environment
    When performing functional test 'test_takeback_move'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Set player levels
    Given the system is in a production-like environment
    When performing functional test 'test_set_player_levels'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Find best move
    Given the system is in a production-like environment
    When performing functional test 'test_find_best_move'
    Then the system should behave as expected
    And all acceptance criteria should be met

  Scenario: Evaluation function
    Given the system is in a production-like environment
    When performing functional test 'test_evaluation_function'
    Then the system should behave as expected
    And all acceptance criteria should be met
