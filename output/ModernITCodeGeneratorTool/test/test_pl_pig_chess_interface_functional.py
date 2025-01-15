```python
import unittest
import chess
from chess_engine import ChessEngine

class TestChessEngine(unittest.TestCase):

    def setUp(self):
        self.engine = ChessEngine()

    def tearDown(self):
        pass

    # 1. End-to-end test scenarios
    def test_new_game_and_bot_play(self):
        self.engine.new_game(white=4, black=4)
        for _ in range(10):
            initial_fen = self.engine.board.fen()
            self.engine.do_bot_move()
            self.assertNotEqual(initial_fen, self.engine.board.fen())

    # 2. Integration test cases
    def test_human_vs_bot_game(self):
        self.engine.new_game(white=0, black=2)
        self.engine.do_move("e2e4")
        self.assertNotEqual(self.engine.board.fen(), chess.STARTING_FEN)
        self.assertTrue(len(self.engine.move_history) == 2)

    # 3. Input/output validation tests
    def test_invalid_move(self):
        self.engine.new_game()
        with self.assertRaises(ValueError):
            self.engine.do_move("e5e7")

    def test_valid_move(self):
        self.engine.new_game()
        self.engine.do_move("e2e4")
        self.assertEqual(self.engine.board.piece_at(chess.E4).symbol(), 'P')

    # 4. Test data setup and cleanup
    def test_new_game_reset(self):
        self.engine.new_game()
        self.engine.do_move("e2e4")
        self.engine.new_game()
        self.assertEqual(self.engine.board.fen(), chess.STARTING_FEN)
        self.assertEqual(len(self.engine.move_history), 0)

    # 5. Error handling scenarios
    def test_move_on_finished_game(self):
        self.engine.board = chess.Board("4k3/8/4K3/8/8/8/8/8 w - - 0 1")  # Stalemate position
        with self.assertRaises(chess.IllegalMoveError):
            self.engine.do_move("e6e7")

    # 6. System integration tests
    def test_custom_starting_position(self):
        custom_fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        self.engine.new_game(start_position=custom_fen)
        self.assertEqual(self.engine.board.fen(), custom_fen)

    # 7. Performance test cases
    def test_evaluation_speed(self):
        import time
        start_time = time.time()
        for _ in range(1000):
            self.engine.evaluate_position()
        end_time = time.time()
        self.assertLess(end_time - start_time, 1.0)  # Should evaluate 1000 positions in less than 1 second

    # Additional test cases
    def test_takeback_move(self):
        self.engine.new_game()
        self.engine.do_move("e2e4")
        self.engine.do_move("e7e5")
        initial_fen = self.engine.board.fen()
        self.engine.takeback_move()
        self.assertNotEqual(initial_fen, self.engine.board.fen())
        self.assertEqual(len(self.engine.move_history), 1)

    def test_set_player_levels(self):
        self.engine.new_game(white=0, black=0)
        self.engine.set_white(4)
        self.assertEqual(self.engine.white_level, 4)
        self.engine.set_black(6)
        self.assertEqual(self.engine.black_level, 6)

    def test_find_best_move(self):
        self.engine.new_game()
        best_move = self.engine.find_best_move(depth=3)
        self.assertIsNotNone(best_move)
        self.assertIn(best_move, self.engine.board.legal_moves)

    def test_evaluation_function(self):
        self.engine.board = chess.Board()
        initial_eval = self.engine.evaluate_position()
        self.engine.do_move("e2e4")
        new_eval = self.engine.evaluate_position()
        self.assertNotEqual(initial_eval, new_eval)

if __name__ == '__main__':
    unittest.main()
```

This test suite covers various aspects of the ChessEngine class:

1. All necessary imports are included at the top of the file.
2. End-to-end test scenarios are covered in `test_new_game_and_bot_play`.
3. Integration test cases are included in `test_human_vs_bot_game`.
4. Input/output validation tests are covered in `test_invalid_move` and `test_valid_move`.
5. Test data setup and cleanup are handled in `setUp`, `tearDown`, and `test_new_game_reset`.
6. Error handling scenarios are tested in `test_move_on_finished_game`.
7. System integration tests are included in `test_custom_starting_position`.
8. A basic performance test is implemented in `test_evaluation_speed`.

Additional test cases cover various functionalities of the ChessEngine class, such as taking back moves, setting player levels, finding the best move, and testing the evaluation function.

To run these tests, save them in a file (e.g., `test_chess_engine.py`) and execute it with Python. Make sure the `chess_engine.py` file containing the ChessEngine class is in the same directory or in the Python path.

Note: This test suite assumes that the ChessEngine class is in a file named `chess_engine.py`. Adjust the import statement if the file name is different.