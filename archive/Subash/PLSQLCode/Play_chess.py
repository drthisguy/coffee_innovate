import chess
from pl_pig_chess_interface import ChessEngine as Interface
from pl_pig_chess_engine_eval import ChessEngineEval
from pl_pig_chess_engine import ChessGame

def get_user_move(board):
    while True:
        try:
            move_uci = input("Enter your move (in UCI format, e.g., 'e2e4'): ")
            move = chess.Move.from_uci(move_uci)
            if move in board.legal_moves:
                return move
            else:
                print("Invalid move. Please try again.")
        except ValueError:
            print("Invalid input. Please use UCI format (e.g., 'e2e4').")

def main():
    interface = Interface()
    evaluator = ChessEngineEval()
    game = ChessGame()

    # Initialize the game
    board = chess.Board()
    interface.new_game()

    for turn in range(5):
        print(f"\nTurn {turn + 1}")
        print(board)

        # User's move
        print("Your turn (White):")
        user_move = get_user_move(board)
        board.push(user_move)
        interface.do_move(user_move.uci())
        print(f"You moved: {user_move.uci()}")

        if board.is_game_over():
            break

        # Computer's move
        print("\nComputer's turn (Black):")
        computer_move = interface.find_best_move(3)  # depth 3
        if computer_move:
            board.push(computer_move)
            interface.do_move(computer_move.uci())
            print(f"Computer moved: {computer_move.uci()}")
        else:
            print("Computer couldn't find a valid move.")
            break

        if board.is_game_over():
            break

    print("\nFinal board state:")
    print(board)

    if board.is_checkmate():
        print("Checkmate!")
    elif board.is_stalemate():
        print("Stalemate!")
    elif board.is_insufficient_material():
        print("Draw due to insufficient material!")
    elif board.can_claim_draw():
        print("Draw can be claimed!")
    else:
        print("Game ended without a conclusive result.")

if __name__ == "__main__":
    main()