Here's comprehensive documentation for the PL/SQL package PL_PIG_CHESS_INTERFACE:

1. Overview and Purpose:
The PL_PIG_CHESS_INTERFACE package provides an interface for interacting with a chess engine (PL_PIG_CHESS_ENGINE) using DBMS_OUTPUT. It allows users to play chess games against the engine, set up specific board positions, and run various test suites to evaluate the engine's performance.

2. Detailed Procedure/Function Descriptions:

a) NEW_GAME:
   Initializes a new chess game with specified parameters.

b) DO_MOVE:
   Executes a chess move for the human player.

c) DO_BOTMOVE:
   Instructs the engine to make a move.

d) DO_BOTGAME:
   Runs an automated game between two engine players.

e) SET_White/SET_Black:
   Changes the player type (human/engine) for White/Black.

f) TAKEBACK_MOVE/TAKEBACK_MOVES:
   (Not yet implemented) Allows undoing of moves.

g) test_* procedures:
   Run various chess position test suites to evaluate engine performance.

3. Parameters and Return Values:

NEW_GAME parameters:
- White/Black: INTEGER (0=human, 2=low, 4=medium, 6=high engine strength)
- STARTPOSITION: VARCHAR2 (custom start position in FEN format)
- p_TheoryMode: INTEGER (0=no theory, 1=internal theory, 2=opening book)
- p_InteractionMode: INTEGER (0=moves only, 1=with positions, 2/3 not implemented)

DO_MOVE parameter:
- fromto: VARCHAR2 (move in the format 'e2e4' or 'g1f3')

test_* procedures parameters:
- lvl: NUMBER (engine strength level)
- poslow/poshigh: INTEGER (range of positions to test)

4. Dependencies and Prerequisites:
- Requires an active DBMS_OUTPUT
- Depends on PL_PIG_CHESS_ENGINE (not provided in the given code)

5. Usage Examples:
- Play as Black against the engine (low level):
  BEGIN NEW_GAME; END;
  BEGIN DO_MOVE('e7e5'); END;

- Play as White against the engine (high level):
  BEGIN NEW_GAME(0,6); END;
  BEGIN DO_MOVE('e2e4'); END;

- Run engine vs engine game:
  BEGIN NEW_GAME(4,2); END;
  BEGIN DO_BOTGAME; END;

- Analyze a specific position:
  BEGIN NEW_GAME(4,4,'7k/p7/1R5K/6r1/6p1/6P1/8/8 w - - 0 1'); END;

- Run test suite:
  BEGIN test_BKtest(2); END;

6. Best Practices and Considerations:
- Ensure DBMS_OUTPUT is enabled before using the package.
- Use appropriate engine strength levels based on the desired difficulty.
- When testing, consider running multiple strength levels for comprehensive results.
- Be aware that some features (e.g., TAKEBACK_MOVE) are not yet implemented.
- For complex analyses, use higher engine strength levels but be prepared for longer processing times.
- When using custom start positions, ensure they are in valid FEN format.
- Regularly check for updates to the package, as it's currently at version 0.92 and may receive future enhancements.