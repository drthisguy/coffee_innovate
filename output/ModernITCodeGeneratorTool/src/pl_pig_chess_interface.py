import chess
import random
from typing import List, Tuple, Optional

class ChessEngine:
    """Chess engine implementation."""

    def __init__(self):
        self.board = chess.Board()
        self.move_history: List[chess.Move] = []
        self.eval_count = 0
        self.white_level = 2
        self.black_level = 0
        self.theory_mode = 0
        self.interaction_mode = 1

    def new_game(self, white: int = 2, black: int = 0, start_position: str = None,
                 theory_mode: int = 0, interaction_mode: int = 1) -> None:
        """
        Start a new game with specified parameters.

        :param white: White player level (0=human, 2=low, 4=medium, 6=high)
        :param black: Black player level (0=human, 2=low, 4=medium, 6=high)
        :param start_position: Starting position in FEN format
        :param theory_mode: Opening theory mode
        :param interaction_mode: Interaction mode for output
        """
        self.white_level = min(white, 10)
        self.black_level = min(black, 10)
        self.theory_mode = theory_mode
        self.interaction_mode = interaction_mode

        if start_position:
            self.board = chess.Board(start_position)
        else:
            self.board = chess.Board()

        self.move_history = []
        self.eval_count = 0

        self.output_position()

        if (not self.board.turn and self.white_level > 0) or (self.board.turn and self.black_level > 0):
            self.do_bot_move()

    def do_move(self, move_str: str) -> None:
        """
        Make a move on the board.

        :param move_str: Move in UCI format (e.g., 'e2e4')
        """
        move = chess.Move.from_uci(move_str)
        if move in self.board.legal_moves:
            self.board.push(move)
            self.move_history.append(move)
            self.output_position()

            if ((not self.board.turn and self.white_level > 0) or 
                (self.board.turn and self.black_level > 0)):
                self.do_bot_move()
        else:
            print(f"Illegal move: {move_str}")

    def do_bot_move(self, overrule_level: int = 0) -> None:
        """
        Make a move for the bot.

        :param overrule_level: Override the bot's level
        """
        level = self.get_bot_level(overrule_level)
        best_move = self.find_best_move(level)

        if best_move:
            self.board.push(best_move)
            self.move_history.append(best_move)
            self.output_position()

            print(f"Bot move: {best_move.uci()}")
            
            if self.board.is_game_over():
                print("Game over")
                print(self.board.result())

    def get_bot_level(self, overrule_level: int) -> int:
        """
        Get the bot's level for the current move.

        :param overrule_level: Override level
        :return: Bot's level
        """
        if overrule_level > 0:
            return max(1, (overrule_level * 3 // 2) - 2)
        elif self.board.turn:
            return max(1, (self.black_level * 3 // 2) - 2)
        else:
            return max(1, (self.white_level * 3 // 2) - 2)

    def find_best_move(self, depth: int) -> Optional[chess.Move]:
        """
        Find the best move for the current position.

        :param depth: Search depth
        :return: Best move found
        """
        best_move = None
        best_value = float('-inf') if self.board.turn else float('inf')

        for move in self.board.legal_moves:
            self.board.push(move)
            value = self.minimax(depth - 1, float('-inf'), float('inf'), not self.board.turn)
            self.board.pop()

            if self.board.turn and value > best_value:
                best_value = value
                best_move = move
            elif not self.board.turn and value < best_value:
                best_value = value
                best_move = move

        return best_move

    def minimax(self, depth: int, alpha: float, beta: float, maximizing_player: bool) -> float:
        """
        Minimax algorithm with alpha-beta pruning.

        :param depth: Current search depth
        :param alpha: Alpha value for pruning
        :param beta: Beta value for pruning
        :param maximizing_player: True if maximizing, False if minimizing
        :return: Evaluation score
        """
        if depth == 0 or self.board.is_game_over():
            return self.evaluate_position()

        if maximizing_player:
            max_eval = float('-inf')
            for move in self.board.legal_moves:
                self.board.push(move)
                eval = self.minimax(depth - 1, alpha, beta, False)
                self.board.pop()
                max_eval = max(max_eval, eval)
                alpha = max(alpha, eval)
                if beta <= alpha:
                    break
            return max_eval
        else:
            min_eval = float('inf')
            for move in self.board.legal_moves:
                self.board.push(move)
                eval = self.minimax(depth - 1, alpha, beta, True)
                self.board.pop()
                min_eval = min(min_eval, eval)
                beta = min(beta, eval)
                if beta <= alpha:
                    break
            return min_eval

    def evaluate_position(self) -> float:
        """
        Evaluate the current board position.

        :return: Evaluation score
        """
        self.eval_count += 1

        if self.board.is_checkmate():
            return float('-inf') if self.board.turn else float('inf')
        
        if self.board.is_stalemate() or self.board.is_insufficient_material():
            return 0

        piece_values = {
            chess.PAWN: 100,
            chess.KNIGHT: 320,
            chess.BISHOP: 330,
            chess.ROOK: 500,
            chess.QUEEN: 900,
            chess.KING: 20000
        }

        score = 0
        for square in chess.SQUARES:
            piece = self.board.piece_at(square)
            if piece:
                value = piece_values[piece.piece_type]
                if piece.color == chess.WHITE:
                    score += value
                else:
                    score -= value

        return score

    def output_position(self) -> None:
        """Output the current board position."""
        if self.interaction_mode in (0, 1):
            print(self.board)
            print(f"FEN: {self.board.fen()}")

    def set_white(self, level: int) -> None:
        """
        Set the white player's level.

        :param level: New level for white
        """
        self.white_level = level
        if not self.board.turn and self.white_level > 0:
            self.do_bot_move()

    def set_black(self, level: int) -> None:
        """
        Set the black player's level.

        :param level: New level for black
        """
        self.black_level = level
        if self.board.turn and self.black_level > 0:
            self.do_bot_move()

    def takeback_move(self) -> None:
        """Take back the last move."""
        if self.move_history:
            self.board.pop()
            self.move_history.pop()
            self.output_position()

    def takeback_moves(self) -> None:
        """Take back the last two moves."""
        for _ in range(2):
            self.takeback_move()

# Test functions (simplified versions of the original test procedures)

def test_position(engine: ChessEngine, fen: str, depth: int) -> None:
    """
    Test the engine on a specific position.

    :param engine: ChessEngine instance
    :param fen: FEN string of the position to test
    :param depth: Search depth
    """
    engine.new_game(depth, depth, fen, 0, 0)
    best_move = engine.find_best_move(depth)
    print(f"Best move: {best_move}")
    print(f"Evaluation count: {engine.eval_count}")

def run_test_suite(engine: ChessEngine, positions: List[str], depth: int) -> None:
    """
    Run a test suite on the engine.

    :param engine: ChessEngine instance
    :param positions: List of FEN strings to test
    :param depth: Search depth
    """
    for i, fen in enumerate(positions, 1):
        print(f"Position {i}:")
        test_position(engine, fen, depth)
        print()

# Example usage:
if __name__ == "__main__":
    engine = ChessEngine()
    
    # Start a new game
    engine.new_game()

    # Make some moves
    engine.do_move("e2e4")
    engine.do_move("e7e5")
    engine.do_move("g1f3")

    # Set bot levels
    engine.set_white(4)
    engine.set_black(2)

    # Let bots play
    for _ in range(10):
        engine.do_bot_move()

    # Take back moves
    engine.takeback_moves()

    # Run a small test suite
    test_positions = [
        "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3",
        "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
    ]
    run_test_suite(engine, test_positions, 4)

