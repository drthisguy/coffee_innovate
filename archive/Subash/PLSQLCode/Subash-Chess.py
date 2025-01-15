import enum
from typing import List, Dict, Optional, Tuple, Set
from dataclasses import dataclass
import array
import time

class Pieces:
    """Chess piece constants using ASCII values"""
    WHITE_KNIGHT = 115  # 's'
    BLACK_KNIGHT = 83   # 'S'
    WHITE_BISHOP = 108  # 'l'
    BLACK_BISHOP = 76   # 'L'
    WHITE_ROOK = 116    # 't'
    BLACK_ROOK = 84     # 'T'
    WHITE_ROOK_CASTLE = 114  # 'r'
    BLACK_ROOK_CASTLE = 82   # 'R'
    WHITE_QUEEN = 100   # 'd'
    BLACK_QUEEN = 68    # 'D'
    WHITE_PAWN = 98     # 'b'
    BLACK_PAWN = 66     # 'B'
    WHITE_PAWN_EP = 101 # 'e'
    BLACK_PAWN_EP = 69  # 'E'
    WHITE_KING = 107    # 'k'
    BLACK_KING = 75     # 'K'
    WHITE_KING_CASTLE = 109  # 'm'
    BLACK_KING_CASTLE = 77   # 'M'
    SPACE = 32  # ' '
    EDGE = 46   # '.'

class MoveType(enum.IntFlag):
    """Move types as bit flags"""
    NORMAL = 0
    EN_PASSANT = 1
    CASTLING = 2
    STALEMATE = 4
    CHECKMATE = 8
    CAPTURE = 16
    CHECK = 32
    PROMOTION = 64
    REPETITION = 128

@dataclass
class Move:
    """Move data structure"""
    from_square: int = 0
    to_square: int = 0
    move_type: MoveType = MoveType.NORMAL
    value: int = 0

class ChessEngine:
    def __init__(self):
        self.board = array.array('b', [Pieces.EDGE] * 120)  # 10x12 board with padding
        self.whites_turn = True
        self.move_history: List[Move] = []
        self.piece_values = {
            Pieces.WHITE_PAWN: 100,
            Pieces.BLACK_PAWN: 100,
            Pieces.WHITE_KNIGHT: 300,
            Pieces.BLACK_KNIGHT: 300,
            Pieces.WHITE_BISHOP: 300,
            Pieces.BLACK_BISHOP: 300,
            Pieces.WHITE_ROOK: 500,
            Pieces.BLACK_ROOK: 500,
            Pieces.WHITE_QUEEN: 900,
            Pieces.BLACK_QUEEN: 900,
            Pieces.WHITE_KING: 20000,
            Pieces.BLACK_KING: 20000
        }
        self.initialize_board()

    def initialize_board(self, fen: str = ''):
        """Initialize chess board from FEN string or default position"""
        if not fen:
            # Default starting position
            fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
        self._parse_fen(fen)

    def _parse_fen(self, fen: str):
        """Parse FEN string and set up board"""
        parts = fen.split()
        board = parts[0]
        rank = 7
        file = 0
        
        for c in board:
            if c == '/':
                rank -= 1
                file = 0
            elif c.isdigit():
                file += int(c)
            else:
                square = rank * 10 + file + 21
                piece = self._fen_to_piece(c)
                self.board[square] = piece
                file += 1
        
        self.whites_turn = parts[1] == 'w'

    def get_next_move(self, position: int, target: int, direction: int, move_type: MoveType) -> Tuple[int, int, int, MoveType]:
        """Find next legal move for a piece"""
        while True:
            target += direction
            if self.board[target] == Pieces.EDGE:
                return position, 89, 0, MoveType.NORMAL
                
            if self.board[target] == Pieces.SPACE:
                if self._is_legal_move(Move(position, target, move_type)):
                    return position, target, direction, MoveType.NORMAL
                continue
                
            if self._is_enemy_piece(target):
                if self._is_legal_move(Move(position, target, move_type | MoveType.CAPTURE)):
                    return position, target, direction, MoveType.CAPTURE
                return position, 89, 0, MoveType.NORMAL
                
            return position, 89, 0, MoveType.NORMAL

    def make_move(self, move: Move) -> bool:
        """Make a move on the board"""
        if not self._is_legal_move(move):
            return False
            
        # Store captured piece
        captured = self.board[move.to_square]
        
        # Move piece
        self.board[move.to_square] = self.board[move.from_square]
        self.board[move.from_square] = Pieces.SPACE
        
        # Handle special moves
        if move.move_type & MoveType.CASTLING:
            self._handle_castling(move)
        elif move.move_type & MoveType.EN_PASSANT:
            self._handle_en_passant(move)
        elif move.move_type & MoveType.PROMOTION:
            self._handle_promotion(move)
            
        self.whites_turn = not self.whites_turn
        self.move_history.append(move)
        
        return True

    def _unmake_move(self, move: Move):
        """Unmake a move, restoring previous position"""
        # Get piece that was moved
        piece = self.board[move.to_square]
        
        # Restore piece to original square
        self.board[move.from_square] = piece
        self.board[move.to_square] = Pieces.SPACE
        
        # Handle special moves
        if move.move_type & MoveType.CASTLING:
            self._unmake_castling(move)
        elif move.move_type & MoveType.EN_PASSANT:
            self._unmake_en_passant(move)
        elif move.move_type & MoveType.PROMOTION:
            self._unmake_promotion(move)
            
        self.whites_turn = not self.whites_turn
        self.move_history.pop()

    def _is_legal_move(self, move: Move) -> bool:
        """Check if a move is legal"""
        # Make move
        old_piece = self.board[move.to_square]
        self.board[move.to_square] = self.board[move.from_square]
        self.board[move.from_square] = Pieces.SPACE
        
        # Check if king is in check
        legal = not self._is_in_check()
        
        # Unmake move
        self.board[move.from_square] = self.board[move.to_square]
        self.board[move.to_square] = old_piece
        
        return legal

    def _is_in_check(self) -> bool:
        """Check if current player's king is in check"""
        king = Pieces.WHITE_KING if self.whites_turn else Pieces.BLACK_KING
        king_pos = self._find_king()
        
        # Check all enemy pieces for attacks on king
        for square in range(21, 99):
            piece = self.board[square]
            if piece != Pieces.SPACE and piece != Pieces.EDGE:
                if self._attacks_square(square, king_pos):
                    return True
        return False

    def _find_king(self) -> int:
        """Find current player's king position"""
        king = Pieces.WHITE_KING if self.whites_turn else Pieces.BLACK_KING
        for square in range(21, 99):
            if self.board[square] == king:
                return square
        return 0

    def evaluate_position(self) -> int:
        """Evaluate current position"""
        score = 0
        
        # Material count
        for square in range(21, 99):
            piece = self.board[square]
            if piece == Pieces.EDGE:
                continue
                
            value = self.piece_values.get(piece, 0)
            if piece >= Pieces.WHITE_PAWN and piece <= Pieces.WHITE_KING_CASTLE:
                score += value
            elif piece >= Pieces.BLACK_PAWN and piece <= Pieces.BLACK_KING_CASTLE:
                score -= value
                
        # Position evaluation
        score += self._evaluate_position_bonus()
        
        return score if self.whites_turn else -score

    def find_best_move(self, depth: int) -> Optional[Move]:
        """Find best move using minimax with alpha-beta pruning"""
        best_move = None
        alpha = -99999
        beta = 99999
        
        moves = self.generate_moves()
        if not moves:
            return None
            
        for move in moves:
            self.make_move(move)
            score = -self._minimax(depth - 1, -beta, -alpha)
            self._unmake_move(move)
            
            if score > alpha:
                alpha = score
                best_move = move
                
        return best_move

    def generate_moves(self) -> List[Move]:
        """Generate all legal moves for current position"""
        moves = []
        
        for square in range(21, 99):
            piece = self.board[square]
            if piece == Pieces.SPACE or piece == Pieces.EDGE:
                continue
                
            if self.whites_turn and piece >= Pieces.BLACK_PAWN:
                continue
            if not self.whites_turn and piece <= Pieces.WHITE_KING_CASTLE:
                continue
                
            piece_moves = self._generate_piece_moves(square)
            moves.extend(piece_moves)
            
        return moves

    def _generate_piece_moves(self, square: int) -> List[Move]:
        """Generate all legal moves for a piece"""
        piece = self.board[square]
        moves = []
        
        # Get move directions for piece type
        directions = self._get_piece_directions(piece)
        
        # Try each direction
        for direction in directions:
            position = square
            target = square
            
            while True:
                position, target, direction, move_type = self.get_next_move(position, target, direction, MoveType.NORMAL)
                if target == 89:  # No more moves in this direction
                    break
                    
                move = Move(position, target, move_type)
                if self._is_legal_move(move):
                    moves.append(move)
                    
                # Stop after one move for pawns and knights
                if piece in (Pieces.WHITE_PAWN, Pieces.BLACK_PAWN, 
                            Pieces.WHITE_KNIGHT, Pieces.BLACK_KNIGHT):
                    break
                    
        return moves

    def _get_piece_directions(self, piece: int) -> List[int]:
        """Get possible move directions for a piece"""
        if piece in (Pieces.WHITE_PAWN, Pieces.BLACK_PAWN):
            return [10] if piece == Pieces.WHITE_PAWN else [-10]
        elif piece in (Pieces.WHITE_KNIGHT, Pieces.BLACK_KNIGHT):
            return [-21, -19, -12, -8, 8, 12, 19, 21]
        elif piece in (Pieces.WHITE_BISHOP, Pieces.BLACK_BISHOP):
            return [-11, -9, 9, 11]
        elif piece in (Pieces.WHITE_ROOK, Pieces.BLACK_ROOK):
            return [-10, -1, 1, 10]
        elif piece in (Pieces.WHITE_QUEEN, Pieces.BLACK_QUEEN):
            return [-11, -10, -9, -1, 1, 9, 10, 11]
        elif piece in (Pieces.WHITE_KING, Pieces.BLACK_KING):
            return [-11, -10, -9, -1, 1, 9, 10, 11]
        return []

    def _minimax(self, depth: int, alpha: int, beta: int) -> int:
        """Minimax search with alpha-beta pruning"""
        if depth == 0:
            return self.evaluate_position()
            
        moves = self.generate_moves()
        if not moves:
            if self._is_in_check():
                return -99999  # Checkmate
            return 0  # Stalemate
            
        for move in moves:
            self.make_move(move)
            score = -self._minimax(depth - 1, -beta, -alpha)
            self._unmake_move(move)
            
            if score >= beta:
                return beta
            if score > alpha:
                alpha = score
                
        return alpha

# Create engine instance
engine = ChessEngine()

# Initialize with starting position
engine.initialize_board()

# Or initialize with FEN string
engine.initialize_board("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

# Find best move at depth 4
best_move = engine.find_best_move(4)

# Make the move
if best_move:
    engine.make_move(best_move)
