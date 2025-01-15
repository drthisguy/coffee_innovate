Here's a comprehensive documentation for the provided PL/SQL code:

1. Overview and Purpose:
This package body (PL_PIG_CHESS_ENGINE) implements a chess engine in PL/SQL. It includes functionality for move generation, evaluation, opening book handling, and various chess-related utilities. The engine uses a minimax algorithm with alpha-beta pruning for move search and evaluation.

2. Detailed Procedure/Function Descriptions:

a) InitTeo:
- Initializes a micro-opening book with predefined moves.
- Gives the first few moves some randomness.

b) Initialize:
- Initializes move/value lookup data (varrays).

c) GetNextTil:
- Finds the next legal move for a given piece in the current position.
- Handles special moves like castling and en passant.

d) DoMove:
- Executes a move on the board, updating the position.
- Handles special cases like pawn promotions and castling.

e) DoMoveC:
- Similar to DoMove but doesn't require MoveTyp information.
- Faster than DoMoveOK when the move is already validated.

f) CheckSkak:
- Checks if a given square is threatened by the opponent.

g) IkkeSkak:
- Checks if a move is illegal due to putting the king in check.

h) GetNext:
- Finds the next legal move in the position.

i) Mirror:
- Mirrors the position, swapping white and black pieces.

j) DoMoveOk:
- Performs a complete check if a move is legal.
- Generates and executes the move if it's legal.

k) QSortTrk:
- Sorts a list of moves based on their value.

l) Egain:
- Evaluates material gain/loss for a move.

m) QFind:
- Implements quiescence search for move evaluation.

n) Find:
- Recursive move generator and evaluator.

o) FindTrk:
- Entry point for finding the best move in a given position.

3. Parameters and Return Values:
- Most procedures take a 'stilling' parameter representing the board position.
- Many functions return SIMPLE_INTEGER values for move scores or boolean flags.
- Some procedures modify the board state directly (in-out parameters).

4. Dependencies and Prerequisites:
- Requires PL_PIG_CHESS_DATA package for data structures.
- Depends on PL_PIG_CHESS_ENGINE_EVAL package for evaluation functions.
- Uses UTL_RAW for bitwise operations in set implementations.

5. Usage Examples:
- The package is designed to be used in conjunction with PL_PIG_CHESS_INTERFACE for playing games and running test suites.
- Example: FindTrk(stilling, depth, extra, bestMove) to find the best move in a given position.

6. Best Practices and Considerations:
- The engine uses various optimization techniques like varrays and SIMPLE_INTEGER for performance.
- Opening book provides variety in the early game.
- Quiescence search helps in evaluating tactical positions more accurately.
- The engine's strength is estimated to be up to 1600 rating.
- FEN and EPD formats are supported for position input/output.

Note: This documentation provides a high-level overview. For detailed understanding of each function and procedure, refer to the inline comments in the code.