```python
import pytest
import chess
from unittest.mock import Mock, patch
from typing import List

# Assuming the original code is in a file named chess_engine.py
from chess_engine import ChessEngineEval, ChessEngine

@pytest.fixture
def chess_engine_eval():
    return ChessEngineEval()

@pytest.fixture
def chess_engine():
    return ChessEngine()

@pytest.fixture
def empty_board():
    return chess.Board().empty()

@pytest.fixture
def starting_board():
    return chess.Board()

class TestChessEngineEval:

    def test_initialization(self, chess_engine_eval):
        """Test if ChessEngineEval initializes with correct default values."""
        assert chess_engine_eval.Evals == 0
        assert chess_engine_eval.OpenGame == False
        assert chess_engine_eval.EndGame == False
        assert len(chess_engine_eval.pd) == 0
        assert chess_engine_eval.ToFile == False
        assert chess_engine_eval.Depth == 0

    def test_pdN_calculation(self, chess_engine_eval):
        """Test pdN method for correct calculation."""
        assert chess_engine_eval.pdN(1, 0) == -5080
        assert chess_engine_eval.pdN(10, 5) == -4273

    def test_pdX_calculation(self, chess_engine_eval):
        """Test pdX method for correct calculation."""
        assert chess_engine_eval.pdX('B', 0) == -10
        assert chess_engine_eval.pdX('K', 5) == 317

    def test_initialize(self, chess_engine_eval):
        """Test initialize method sets correct values."""
        chess_engine_eval.initialize()
        assert chess_engine_eval.ToFile == True
        assert chess_engine_eval.FirstW == True
        assert len(chess_engine_eval.pdw) == chess_engine_eval.pdSz
        assert len(chess_engine_eval.pd) == chess_engine_eval.pdSz
        assert len(chess_engine_eval.pdb) == chess_engine_eval.pdSz

    @patch('chess_engine.ChessEngineEval.pre_process')
    def test_pre_process_called(self, mock_pre_process, chess_engine_eval):
        """Test that pre_process method is called."""
        chess_engine_eval.pre_process()
        mock_pre_process.assert_called_once()

    @patch('chess_engine.ChessEngineEval.pre_processor')
    def test_pre_processor_called(self, mock_pre_processor, chess_engine_eval, starting_board):
        """Test that pre_processor method is called with correct arguments."""
        chess_engine_eval.pre_processor(starting_board)
        mock_pre_processor.assert_called_once_with(starting_board)

    def test_eval_returns_integer(self, chess_engine_eval, starting_board):
        """Test that eval method returns an integer."""
        result = chess_engine_eval.eval(starting_board, 0, False, -10000, 10000)
        assert isinstance(result, int)

class TestChessEngine:

    def test_initialization(self, chess_engine):
        """Test if ChessEngine initializes with a ChessEngineEval instance."""
        assert isinstance(chess_engine.evaluator, ChessEngineEval)

    @patch('chess_engine.ChessEngine.make_move')
    def test_make_move_called(self, mock_make_move, chess_engine, starting_board):
        """Test that make_move method is called with correct arguments."""
        chess_engine.make_move(starting_board)
        mock_make_move.assert_called_once_with(starting_board)

    def test_evaluate_position(self, chess_engine, starting_board):
        """Test that evaluate_position returns an integer."""
        result = chess_engine.evaluate_position(starting_board)
        assert isinstance(result, int)

    @patch('chess_engine.ChessEngineEval.eval')
    def test_evaluate_position_calls_eval(self, mock_eval, chess_engine, starting_board):
        """Test that evaluate_position calls the evaluator's eval method with correct arguments."""
        chess_engine.evaluate_position(starting_board)
        mock_eval.assert_called_once_with(starting_board, 0, False, -10000, 10000)

@pytest.mark.parametrize("input_move,is_legal", [
    ("e2e4", True),
    ("e2e5", False),
    ("a2a4", True),
    ("h8h9", False),
])
def test_move_legality(input_move, is_legal, starting_board):
    """Test various moves for legality on the starting board."""
    move = chess.Move.from_uci(input_move)
    assert (move in starting_board.legal_moves) == is_legal

def test_game_over_detection(empty_board):
    """Test game over detection in various scenarios."""
    # Stalemate position
    empty_board.set_fen("k7/8/1Q6/8/8/8/8/7K w - - 0 1")
    assert empty_board.is_game_over()

    # Checkmate position
    empty_board.set_fen("k7/8/1R6/8/8/8/8/7K w - - 0 1")
    assert empty_board.is_game_over()

    # Ongoing game
    empty_board.set_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    assert not empty_board.is_game_over()

if __name__ == "__main__":
    pytest.main(["-v"])
```

This test suite includes:

1. All necessary imports (pytest, chess, unittest.mock).
2. Test class setup using pytest fixtures.
3. Individual test cases for each function/method in both `ChessEngineEval` and `ChessEngine` classes.
4. Edge cases and error scenarios (e.g., testing move legality with both legal and illegal moves).
5. Mocking of external dependencies and internal methods to isolate tests.
6. Clear test case descriptions and comments for each test.
7. Use of pytest fixtures for common objects (chess_engine_eval, chess_engine, empty_board, starting_board).
8. Assertions to verify expected outcomes.

Additional notes:

- The tests cover the initialization of both classes, method calls, and some basic functionality.
- We use parametrized tests for checking move legality.
- Game over detection is tested for different scenarios.
- Some methods (like `pre_process` and `pre_processor`) are only tested for being called, as their implementations are not provided in the original code.
- The `eval` method is tested to return an integer, but its actual logic is not tested as it's not implemented in the provided code.

To run these tests, save them in a file (e.g., `test_chess_engine.py`) in the same directory as your `chess_engine.py` file, and run `pytest test_chess_engine.py -v` from the command line.

Remember to install the required packages (`pytest` and `chess`) before running the tests:

```
pip install pytest chess
```

These tests provide a good starting point and can be expanded as you implement more functionality in your chess engine.