DROP PACKAGE BODY PL_PIG_CHESS_ENGINE;

CREATE OR REPLACE PACKAGE BODY PL_PIG_CHESS_ENGINE AS
--
--

-- LICENSE
--
-- PL_PIG_CHESS_ENGINE v 0.92,                  (c) Egon Von Bech Madsen, Denmark (ema@adm.ku.dk) 
--
-- This software is Diceware. Diceware is defined as Freware with one restriction:
--
--   For non-commercial use:
--      roll one dice until you get 6, then take a picture. That picture is your 10 year free license.
--
--   For commercial use of small or medium sized companies (Yearly revenue less than US$ 60 billion), like Oracle:
--      roll two dices until you get 6 6, then take a picture. That picture is your 10 year free license.
--
--   For commercial use of large sized companies (Yearly revenue more than US$ 60 billion), like Microsoft:
--      roll three dices until you get 6 6 6, then take a picture. That picture is your 10 year free license.
--
-- It is allowed to modify and share the code as long as this LICENSE-text is unmodified.
--
-- ****************************************************************************************
-- * Disclaimer (use at your own risk):                                               
-- * Any use of this software is strictly at your own risk, and I will not be liable for 
-- * any losses and damages in connection with the use of this software.
-- ****************************************************************************************
-- LICENSE <end>

-- PL_PIG_CHESS_ENGINE is a Chess Engine written in Oracle PL/SQL.
--
-- HISTORY
-- Migrated from the Engine of PIGbase4 v2.8, coded with M2Amiga Modula-2 v4.2 
--
-- The Engine is 3 packages:
-- PL_PIG_CHESS_ENGINE
-- PL_PIG_CHESS_ENGINE_EVAL
-- PL_PIG_CHESS_DATA
--
-- Also included is a package:
-- PL_PIG_CHESS_INTERFACE 
-- making it possible to play with the Engine and run some test-suites using DBMS_OUTPUT.

-- TECHNICAL (PL/SQL)
-- PL/SQL is a quite restricted and slow language, not the perfect choice for a Chess Engine.
-- If You want top strength, don't use PIG-Chess, but install a Stockfish Engine at Your HOST OS.
--
-- Fair Performance is reached by intensive use of VARRAYS, SIMPLE_INTEGER and INLINE'able SET operators. 
-- And by NOT using SQL features. The many initiations of arrays happens only one time pr session/game.
--
-- TECHNICAL (CHESS)
-- Opening book
-- Static evaluation
-- quiescence deepening minimax algorithm with alpha/beta cut-off and sort for better pruning
-- Q-search (deeper selective search on killer-moves like check)
-- Leaf evaluation
-- Single CPU only
-- Supports 5 levels (from few seconds to several minutes pr move).
-- Rating: up to 1600
-- FEN and EPD is supported.
--
-- INSTALLATION
-- Install the 4 packages on a Oracle database:
-- 1. PL_PIG_CHESS_DATA
-- 2. PL_PIG_CHESS_ENGINE_EVAL
-- 3. PL_PIG_CHESS_ENGINE
-- 4. PL_PIG_CHESS_INTERFACE
--
-- USE:
-- 1. Use SQL*PLUS or Toad/SQL-Developer with DBMS_OUTPUT activated
-- 2. Use examples seen in PL_PIG_CHESS_INTERFACE
--
-- OR:
-- Make your own graphical (APEX?) interface...



/*

               PROCEDURES :

InitTeo :
  Intitiates a micro-opening book, gives first few moves random
Initialize :
  Initiates move/value lookup data (varrays)
GetNextTil :
   finds next legal (white/black) move with current piece in the position, til=fra -> fra=89 when no more
   fra=fra-1 and til=89 to see the possible moves for a piece; 
   And calculates MoveType as used in DoMove and IkkeSkak (not-check)
DoMove :
   Do (white/black) move, already validated OK (by GetNext) 
   pawn-promotions: 20 less then Rook, 30 then kNight, 40 bishop
   MoveTyp MUST be set to enpassant and castling (rokade) when relevant!!! (use DoMoveC) 
DoMoveC :
  As DoMove, but NO MoveTyp information is required
  Faster than DoMoveOK, used when the move is alread validated OK 
CheckSkak :
   checks if field n is threatned by white/black.
IkkeSkak :
   checks if  (white/black) move is illegal p.gr.a. check.
   MoveTyp MUST be set to rokade (castling) and pat (stalemate) when relevant!!!
GetNext :
  finds next legal (white/black) move in the position, fra=89 when no more
  fra=fra-1 and til=89 for lsning af en briks muligheder; 
Mirror :
   Morrors the position, so white/black is swapped
DoMoveOk :
  complete check if move is ok, generates black/white moves using DoMove 
  IF not DoMoveOk() then error.. -> generates a move if it's legal
QSortTrk :
  Sorts a list of moves after value
Equal :
  Compare two positions 
still :
  setup a position from a string in POSITIONSTR format (st='' gives start-position) 
DoMoveC :
  As DoMove, but NO MoveTyp information is required
  Faster than DoMoveOK, used when the move is alread validated OK 
Find :
  recursive move-generator/evaluator
NEq :
    Compare two positions (NotEqual) used by Mikro Openingbook
FindTrk :
  StartStub for Find
ClearHistory :
 clears engine history data 3* array: cnt=1-4,black=colour 

PreProcess  : (Eval)
  sets the pd array..default positional values. The static evaluator
PreProcessor  : (Eval)
  adjusts the pd-array+OpenGame+EngGame according..the actual position. The static evaluator
Eval : (Eval)
  Evaluates a position. The dynamic evaluator

     PROCEDURE overview : if () then in SkakKey,
                          if {} then in SkakBrainX.
                          if (] then in SkakBrainEval

     (CalcMunde)__________{GetV} ______________________________ {GetNextTilV}
                \_________{GetD} ______________ {GetNextD} ____ {GetNextTilD}
                 \________Mirror

     GetMoveNr____
                  \
     GetMove_      \
             \      \
     DoMoveOk_\______\_ GetNext ____________ GetNextTil
               \________ DoMove       \_____ IkkeSkak _____ CheckSkak
     DoMoveC
               _________{InitTeo}
     {Init}___/     
                  _____(PreProcessor]______(PreProcess]
                 /
     FindTrk  __/______ Find _______________ (AEM)
                               \____________+GetNext
                                \___________+DoMove
                                 \__________+Mirror
                                  \_________+IkkeSkak
     (MarkMoves) ______+GetNext    \________ QSortTrk
                                    \_______ (Eval]
*/

  SkakBrainModCompilation CONSTANT VARCHAR2(16) :='1041';
  MaxDistance  CONSTANT  SIMPLE_INTEGER :=  18; -- Location in retn array to store  maxdistance
  DrawAccept   CONSTANT  SIMPLE_INTEGER :=  -25; -- only for repetition: positive=peaceful, default=0
  movetyp     MOVETYPE:=0;
  Traek       TRKDATA;
  TYPE ValueCalcYtype IS VARRAY(53) OF SIMPLE_INTEGER; -- offset= -31 (' '..'T']
  TYPE ValueCalcType  IS VARRAY(20) OF ValueCalcYtype; -- offset= -64 ('A'..'T']
  ValueCalc ValueCalcType := ValueCalcType();
  FraTag        SIMPLE_INTEGER := 0; -- test only (25=e2, 0=all)
  MaxStackDepth SIMPLE_INTEGER := 0; --..avoid stack overrun (45000 stack: max 30)
  BlacksTurn BOOLEAN; -- who is move calculated for, is set by FindTrk
  STOPP      BOOLEAN;
  FirstW   BOOLEAN := FALSE; 

/*
  ValueT CONSTANT SIMPLE_INTEGER  := 470; --rook: danish: Tårn
  ValueR CONSTANT SIMPLE_INTEGER  := 480; --rook (castling possible) danish: tårn (Rokade)
  ValueM CONSTANT SIMPLE_INTEGER  :=9999; --king (castling possible) danish: Konge (Majestæt)
  ValueK CONSTANT SIMPLE_INTEGER  :=9980; --king danish: Konge
  ValueD CONSTANT SIMPLE_INTEGER  := 880; --Queen danish: Dronning
  ValueL CONSTANT SIMPLE_INTEGER  := 300; --Bishop danish: Løber
  Value_S CONSTANT SIMPLE_INTEGER := 300; --knight danish: Springer
  ValueB CONSTANT SIMPLE_INTEGER  := 100; --pawn danish: Bonde
  ValueE CONSTANT SIMPLE_INTEGER  := 100; --pawn (en-passant) danish: bonde (En-passant) 
*/

  TYPE stDarrType IS VARRAY (8) OF SIMPLE_INTEGER;
  stDarr stDarrType := stDarrType(PL_PIG_CHESS_ENGINE_EVAL.ValueB,PL_PIG_CHESS_ENGINE_EVAL.Value_S,PL_PIG_CHESS_ENGINE_EVAL.ValueT,PL_PIG_CHESS_ENGINE_EVAL.ValueD,PL_PIG_CHESS_ENGINE_EVAL.Value_S,PL_PIG_CHESS_ENGINE_EVAL.ValueT,PL_PIG_CHESS_ENGINE_EVAL.ValueK);
  stDcount    CONSTANT SIMPLE_INTEGER :=8;-- før 0
  stDpawns    CONSTANT SIMPLE_INTEGER :=1;
  stDknights  CONSTANT SIMPLE_INTEGER :=2;
  stDbishops  CONSTANT SIMPLE_INTEGER :=2;
  stDrooks    CONSTANT SIMPLE_INTEGER :=3;
  stDqueens   CONSTANT SIMPLE_INTEGER :=4;
  stDbishopsB CONSTANT SIMPLE_INTEGER :=5; --behind Queen 
  stDrooksB   CONSTANT SIMPLE_INTEGER :=6; --behind Queen 
  stDking     CONSTANT SIMPLE_INTEGER :=7;

  StartEval     SIMPLE_INTEGER:=0;
  SkakDepth     SIMPLE_INTEGER:=0;
  XchDepth      SIMPLE_INTEGER:=0;
  MaxPosValGain SIMPLE_INTEGER:=0;
  MaxEvals      SIMPLE_INTEGER:=0; -- not used in Qfind 

  TeoMoves SIMPLE_INTEGER:=0;
  
  HisMax CONSTANT SIMPLE_INTEGER :=20; -- change value in SkakFil.GetStilling too 
        -- 1=White 2=Black 1..HisMax last HisMax positions+moves
  TYPE RepeteYrectype IS RECORD (st PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE,
                                     tr TRKDATA);
  TYPE RepeteYtype IS VARRAY(HisMax) OF RepeteYrectype;                        
  TYPE RepeteXYtype IS VARRAY(2) OF RepeteYtype;-- tidl (FALSE..TRUE) now  --1=FALSE, 2=TRUE 
  Repete RepeteXYtype := RepeteXYtype(); --Detection of same position 3 times within last 20 full-moves

  FirstCall BOOLEAN; -- FindTrk sets, then Find see it's first time
                     -- and resets FirstCall                        
  --TeoNvn CONSTANT varchar2(255) := 'OPENINGS.TXT';
--
--
--compare with simple_integer is double speed than compare with char(1).
--Numeric representation of pieces to get best possible speed:

wN CONSTANT SIMPLE_INTEGER  := 115;--ASCII('s');--White kNight
bN CONSTANT SIMPLE_INTEGER  :=  83;--ASCII('S');--Black kNight
wB CONSTANT SIMPLE_INTEGER  := 108;--ASCII('l');--White Bishop
bB CONSTANT SIMPLE_INTEGER  :=  76;--ASCII('L');--Black Bishop
wR CONSTANT SIMPLE_INTEGER  := 116;--ASCII('t');--White Rook
bR CONSTANT SIMPLE_INTEGER  :=  84;--ASCII('T');--Black Rook
wC CONSTANT SIMPLE_INTEGER  := 114;--ASCII('r');--White rook with Castling
bC CONSTANT SIMPLE_INTEGER  :=  82;--ASCII('R');--Black rook with Castling
wQ CONSTANT SIMPLE_INTEGER  := 100;--ASCII('d');--White Queen
bQ CONSTANT SIMPLE_INTEGER  :=  68;--ASCII('D');--Black Queen
wP CONSTANT SIMPLE_INTEGER  :=  98;--ASCII('b');--White Pawn
bP CONSTANT SIMPLE_INTEGER  :=  66;--ASCII('B');--Black Pawn
wE CONSTANT SIMPLE_INTEGER  := 101;--ASCII('e');--White pawn En-passant
bE CONSTANT SIMPLE_INTEGER  :=  69;--ASCII('E');--Black pawn En-passant
wK CONSTANT SIMPLE_INTEGER  := 107;--ASCII('k');--White King
bK CONSTANT SIMPLE_INTEGER  :=  75;--ASCII('K');--Black King
wM CONSTANT SIMPLE_INTEGER  := 109;--ASCII('m');--White Majesty (king w castling)
bM CONSTANT SIMPLE_INTEGER  :=  77;--ASCII('M');--Black Majesty (king w castling)
wA CONSTANT SIMPLE_INTEGER  :=  97;--ASCII('a');--White pieces all bigger than this
bA CONSTANT SIMPLE_INTEGER  :=  65;--ASCII('A');--Pieces all bigger than this + reference index
wT CONSTANT SIMPLE_INTEGER  :=  72;--ASCII('H');--Whites Turn (index hvistur)
bT CONSTANT SIMPLE_INTEGER  :=  83;--ASCII('S');--Blacks Turn (index hvistur)
spc CONSTANT SIMPLE_INTEGER :=  32;--ASCII(' ');--Space
edge CONSTANT SIMPLE_INTEGER:=  46;--ASCII('.');--Edge-marker

FUNCTION UPPER_n(n SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
BEGIN
  IF n<wA THEN
    RETURN n;
  ELSE 
    RETURN n - 32;
  END IF;
END UPPER_n;
--
FUNCTION pdN(brik_n SIMPLE_INTEGER, felt SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
BEGIN -- two-dimensional array (bP..wR, 11..88) -> 1..3978. Here index is calculated out of Numeric repræsentation (ascii value) of pieces.
  --RETURN (brik - 66) * 78 + felt - 10; -- ASCII(bP)=66  ASCII(wR)=116
  RETURN brik_n * 78 -5158 + felt; -- ASCII(bP)=66
END pdN;

/*
  logical structure for a position :
    RECORD
      stilling :ARRAY(-1..11,-1..11] OF BRIK;
      hvistur  :BOOLEAN;
    END;
  where 1,1 -> 8,8  A1 -> H8 , so 11-88 is A1-H8
  and the rest is a doubbel edge ('.') to catch movegenerator when hitting outside the board
   
  capitalized pieces is Black. Names is from danish.
  
  The en-passant and castling rights is implicit stored by changing the piecenames.
  Example: First time a Rook moves, it will change name, to tell it can not be used for castling.
  Example: An unmoved king have extended moves (two to right or left), supporting castling in a simple way (quicker)
  
  retn contains data to generate the legal moves. Every piece (brik) has
  a number of direction (retning) vectors (4-8) and a MaxDistance (RQB=TRDL=8, PNK=BSKM=1).
  retn(brik,MaxDistance]
  retn(brik,0]           indeholder første retning.
  retn(brik,retning]     indeholder så næste retning indtil den er 0.

  The knight is MaxDistance=1 an eight directionvektors pointing
  directly on fields, of possible moves.

  Promotion to other than Queen is registred in 'to' as: 20 less then Rook, 30 then kNight, 40 bishop
  If black then it is registred in 'to' as: 20 more then Rook, 30 then kNight, 40 bishop (
  Example: move a7-a8(Q) is stored 71->81 while a7-a8(N) is stored 71->51

  retn is a sparse matrice. 20x43x2=1.6 Kbytes keep 63 bytes (4%). 
  But lookup is fastest so this physical representation is preferred.
*/
--
PROCEDURE WRT(s VARCHAR2) IS
--for tests/debug only
BEGIN
  dbms_output.put_line('PL '||s);
END WRT;
--

--
-- ************************************************************************************************
-- ***********    PL/SQL high-performance implementation of sets (of up to 31 members)    *********
--
-- supports UNION, INTERSECT, COMPLEMENT (MINUS), IN, XOR and (kind of) named members 
--
--  By using one 32 bit (not-null) simple_integer to hold a set, its possible to implement sets in pl/sql like found in other 
--  Block-structured languages. At the same time, the performance will be far better than other techniques on pl/sql.     
--
--
-- To get best performance (upto twice the 'normal'):
--    Copy all functions to be local in your package                           -- makes it possible to use inline optimization. 
--    alter session set plsql_optimize_level =3;                               -- will then use inline optimation. 
--    alter procedure <name> compile plsql_code_type=NATIVE plsql_debug=FALSE; -- Will Compile Your package NATIVE 
--
FUNCTION SET_IN(members BINARY_INTEGER, setM BINARY_INTEGER) return BOOLEAN IS
BEGIN -- IN: member of set (M n N)
RETURN UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_and(UTL_RAW.CAST_FROM_BINARY_INTEGER(members),UTL_RAW.CAST_FROM_BINARY_INTEGER(setM)))=members;
END;
--
FUNCTION SET_INTERSECT(setM BINARY_INTEGER, setN BINARY_INTEGER) return BINARY_INTEGER IS
BEGIN -- intersection (M n N), uses AND
RETURN UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_and(UTL_RAW.CAST_FROM_BINARY_INTEGER(setM),UTL_RAW.CAST_FROM_BINARY_INTEGER(setN)));
END;
--
FUNCTION SET_UNION(setM BINARY_INTEGER, setN BINARY_INTEGER) return BINARY_INTEGER IS
BEGIN -- union set (M u N), uses OR
RETURN UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_or(UTL_RAW.CAST_FROM_BINARY_INTEGER(setM),UTL_RAW.CAST_FROM_BINARY_INTEGER(setN)));
END;
--
PROCEDURE SET_INCL(setM in out BINARY_INTEGER, members BINARY_INTEGER) IS
BEGIN -- include member(s) to set (M u N), uses OR
  setM := UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_or(UTL_RAW.CAST_FROM_BINARY_INTEGER(setM),UTL_RAW.CAST_FROM_BINARY_INTEGER(members)));
END;
--
FUNCTION SET_XOR(setM BINARY_INTEGER, setN BINARY_INTEGER) return BINARY_INTEGER IS
BEGIN -- difference set, uses XOR 
RETURN UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_xor(UTL_RAW.CAST_FROM_BINARY_INTEGER(setM),UTL_RAW.CAST_FROM_BINARY_INTEGER(setN)));
END;
/*
FUNCTION SET_DIFF(setM BINARY_INTEGER, setN BINARY_INTEGER) return BINARY_INTEGER IS
BEGIN -- -- Difference set (M c N), uses COMPLEMENT(M) AND N (DO NOT USE, as COMPLEMENT can do the same (reverse parameters) and XOR gives more real difference.
RETURN UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_and(UTL_RAW.bit_complement(UTL_RAW.CAST_FROM_BINARY_INTEGER(setM)),UTL_RAW.CAST_FROM_BINARY_INTEGER(setN)));
END;*/
--
FUNCTION SET_COMPLEMENT(setM BINARY_INTEGER, setN BINARY_INTEGER) return BINARY_INTEGER IS 
BEGIN -- Complementary set (M \ N or M minus N), uses COMPLEMENT(N) AND M
RETURN UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_and(UTL_RAW.bit_complement(UTL_RAW.CAST_FROM_BINARY_INTEGER(setN)),UTL_RAW.CAST_FROM_BINARY_INTEGER(setM)));
END;
--
FUNCTION MEMBER_KEY(memberno simple_integer) return simple_integer IS
-- member key (from its member number to its internal value)
res simple_integer := 1;
n simple_integer := 0;
BEGIN -- intern key for member nr (1..31)
IF memberno = 0 THEN RETURN 0;
ELSIF memberno between 1 and 31 THEN
FOR n IN 2..memberno LOOP
res := res * 2;
END LOOP;
RETURN res;
ELSE
RETURN -1;
END IF;
END;
--
FUNCTION MEMBER_NO(memberkey simple_integer) return simple_integer IS
-- member number (from its internal value)
res simple_integer := 1;
n simple_integer := 0;
BEGIN -- member nr (1..31) for intern key
IF memberkey = 0 THEN RETURN 0; END IF;
IF memberkey = 1 THEN RETURN 1; END IF;
FOR n IN 2..31 LOOP
res := res * 2;
--WRT(res||' key:'||memberkey);
IF memberkey = res THEN RETURN n; END IF;
END LOOP;
RETURN -1;
END;
--
FUNCTION TO_BINSTR(setM BINARY_INTEGER) RETURN VARCHAR2 IS
-- converts a set to a string in binary format
hex VARCHAR2(80);
res VARCHAR2(80);
BEGIN
hex :=ltrim(to_char(setM,'XXXXXXXX'));
IF LENGTH(hex) = 1 THEN
hex := '000'||hex;
ELSIF LENGTH(hex) = 2 THEN
hex := '00'||hex;
ELSIF LENGTH(hex) = 3 THEN
hex := '0'||hex;
END IF;
--WRT('"'||hex||'"');
FOR n in 1..LENGTH(hex) LOOP
res := res||
CASE substr(hex,n,1)
WHEN '0' THEN '0000'
WHEN '1' THEN '0001'
WHEN '2' THEN '0010'
WHEN '3' THEN '0011'
WHEN '4' THEN '0100'
WHEN '5' THEN '0101'
WHEN '6' THEN '0110'
WHEN '7' THEN '0111'
WHEN '8' THEN '1000'
WHEN '9' THEN '1001'
WHEN 'A' THEN '1010'
WHEN 'B' THEN '1011'
WHEN 'C' THEN '1100'
WHEN 'D' THEN '1101'
WHEN 'E' THEN '1110'
WHEN 'F' THEN '1111'
ELSE '____' END; 
END LOOP;
RETURN res;
END;
-- *********   END END END  PL/SQL high-performance implementation of sets END END END    *********
-- ************************************************************************************************
-- 
--
FUNCTION STILLING_TO_EPD(stilling PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, operationlist VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
--Converts a position from internal array format to a string in EPD format
--Possible to add EPD operations. Example: 'bm Nf3; id "test1";'
 HJ_EPD VARCHAR2(255):='';
 SPCC SIMPLE_INTEGER :=0;
 n   SIMPLE_INTEGER :=0;
 rwa BOOLEAN := FALSE;--  rook-white A castle
 rba BOOLEAN := FALSE;--  rook-black A castle
 rwh BOOLEAN := FALSE;--  rook-white H castle
 rbh BOOLEAN := FALSE;--  rook-black H castle
 kw  BOOLEAN := FALSE;--  king-white castle
 kb  BOOLEAN := FALSE;--  king-black castle
 ep  VARCHAR2(2) := ''; --en-passant field
 ch  SIMPLE_INTEGER :=0;
BEGIN
  FOR y IN 1..8 LOOP
    FOR x IN 1..8 LOOP
      n:=10*(9-y)+x;
      ch := stilling(stOff+ n);
      IF ch=spc THEN  
        SPCC := SPCC + 1;
      ELSE
        IF SPCC > 0 THEN
          HJ_EPD:= HJ_EPD||TO_CHAR(SPCC);
          SPCC := 0;
        END IF;
        CASE CH
           WHEN bP THEN HJ_EPD:= HJ_EPD||'p';
           WHEN bE THEN HJ_EPD:= HJ_EPD||'p'; ep :=  CHR(ASCII(x)+48)||'6';
           WHEN bR THEN HJ_EPD:= HJ_EPD||chr(wC);
           WHEN bC THEN HJ_EPD:= HJ_EPD||chr(wC); IF x=1 THEN rba := TRUE; ELSIF x=8 THEN rbh := TRUE; END IF;
           WHEN bK THEN HJ_EPD:= HJ_EPD||chr(wK); 
           WHEN bM THEN HJ_EPD:= HJ_EPD||chr(wK); kb := TRUE;
           WHEN bB THEN HJ_EPD:= HJ_EPD||chr(wP);
           WHEN bN THEN HJ_EPD:= HJ_EPD||'n';
           WHEN bQ THEN HJ_EPD:= HJ_EPD||'q';
           WHEN wP THEN HJ_EPD:= HJ_EPD||'P';
           WHEN wE THEN HJ_EPD:= HJ_EPD||'P'; ep :=  CHR(ASCII(x)+48)||'3';
           WHEN wR THEN HJ_EPD:= HJ_EPD||chr(bC);
           WHEN wC THEN HJ_EPD:= HJ_EPD||chr(bC); IF x=1 THEN rwa := TRUE; ELSIF x=8 THEN rwh := TRUE; END IF;
           WHEN wK THEN HJ_EPD:= HJ_EPD||chr(bK);
           WHEN wM THEN HJ_EPD:= HJ_EPD||chr(bK); kw := TRUE;
           WHEN wB THEN HJ_EPD:= HJ_EPD||chr(bP);
           WHEN wN THEN HJ_EPD:= HJ_EPD||'N';
           WHEN wQ THEN HJ_EPD:= HJ_EPD||'Q';
        END CASE;
      END IF;
    END LOOP;
    IF SPCC > 0 THEN
      HJ_EPD:= HJ_EPD||TO_CHAR(SPCC);
      SPCC := 0;
    END IF;
    IF y < 8 THEN HJ_EPD:= HJ_EPD||'/'; END IF;
  END LOOP;
  --
  IF stilling(stOff+ HvisTur) = bN THEN
    HJ_EPD:= HJ_EPD||' b';
  ELSE 
    HJ_EPD:= HJ_EPD||' w';
  END IF;
  --
  IF kw OR kb THEN
    HJ_EPD:= HJ_EPD||' '||CASE WHEN rwh THEN chr(bK) END||CASE WHEN rwa THEN 'Q' END||CASE WHEN rbh THEN chr(wK) END||CASE WHEN rba THEN 'q' END;  
  ELSE
    HJ_EPD:= HJ_EPD||' -';
  END IF;
  --
  IF ep IS NULL THEN
    HJ_EPD:= HJ_EPD||' -';
  ELSE
    HJ_EPD:= HJ_EPD||' '||ep;
  END IF;  
  --
  IF operationlist is NULL THEN
    RETURN HJ_EPD;
  ELSE
    RETURN HJ_EPD||' '||ltrim(operationlist);
  END IF;
EXCEPTION 
  WHEN OTHERS THEN
    RETURN(substr(sqlerrm,1,200));
END STILLING_TO_EPD;   
         

FUNCTION FEN_EPD_TO_STR(FEN_EPD VARCHAR2) RETURN VARCHAR2 IS
-- converts a position in FEN or EPD format to POSITIONSTR format.
 HJ_FEN_EPD VARCHAR2(255):=REPLACE(REPLACE(FEN_EPD,chr(10)),chr(13));
 sla  INTEGER;
 sla2 INTEGER;
 HJ_S VARCHAR2(50);
 HJ_LIN VARCHAR2(18);
 HJ_STR VARCHAR2(89):='';
 Ra VARCHAR2(8);
 ep VARCHAR2(1);
BEGIN
   IF FEN_EPD IS NULL THEN RETURN NULL; END IF;
   FOR cRank in 1..8 LOOP
      IF cRank < 8 THEN
        sla :=INSTR(HJ_FEN_EPD,'/');
        IF sla=0 THEN RETURN 'missing slash!'; END IF;-- ! in returnvalue signals an error
      ELSE 
        sla :=INSTR(HJ_FEN_EPD,' ');
        IF sla=0 THEN RETURN 'missing space!'; END IF;-- ! in returnvalue signals an error
      END IF;
      Ra := substr(HJ_FEN_EPD,1,sla-1);
      HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+1);
      IF Ra='8' THEN 
        HJ_LIN := '        ';
      ELSE
        HJ_LIN := '';
        LOOP
          EXIT WHEN Ra IS NULL;
          CASE SUBSTR(Ra,1,1)
            WHEN '1' THEN HJ_LIN := HJ_LIN||' ';
            WHEN '2' THEN HJ_LIN := HJ_LIN||'  ';
            WHEN '3' THEN HJ_LIN := HJ_LIN||'   ';
            WHEN '4' THEN HJ_LIN := HJ_LIN||'    ';
            WHEN '5' THEN HJ_LIN := HJ_LIN||'     ';
            WHEN '6' THEN HJ_LIN := HJ_LIN||'      ';
            WHEN '7' THEN HJ_LIN := HJ_LIN||'       ';
            WHEN 'r' THEN HJ_LIN := HJ_LIN||'T';
            WHEN 'b' THEN HJ_LIN := HJ_LIN||'L';
            WHEN 'q' THEN HJ_LIN := HJ_LIN||'D';
            WHEN 'n' THEN HJ_LIN := HJ_LIN||'S';
            WHEN 'p' THEN HJ_LIN := HJ_LIN||'B';
            WHEN 'k' THEN HJ_LIN := HJ_LIN||'K';
            WHEN 'R' THEN HJ_LIN := HJ_LIN||'t';
            WHEN 'B' THEN HJ_LIN := HJ_LIN||'l';
            WHEN 'Q' THEN HJ_LIN := HJ_LIN||'d';
            WHEN 'N' THEN HJ_LIN := HJ_LIN||'s';
            WHEN 'P' THEN HJ_LIN := HJ_LIN||'b';
            WHEN 'K' THEN HJ_LIN := HJ_LIN||'k';
            ELSE RETURN 'illegal '||cRank||' ranki ('||Ra||')!'; -- ! in returnvalue signals an error
          END CASE;
          IF length(hj_lin)> 8 THEN
            RETURN 'Rank '||cRank||' > 8 ('||hj_lin||')!';
          END IF;
          Ra := SUBSTR(Ra,2);
        END LOOP;
      END IF;
      HJ_STR := HJ_STR||hj_lin;
   END LOOP;
   --<Side to move> 
   IF substr(HJ_FEN_EPD,1,1)= 'w' THEN
     HJ_STR := HJ_STR||'H';
   ELSIF substr(HJ_FEN_EPD,1,1)= 'b' THEN
     HJ_STR := HJ_STR||'S';
   ELSE
     RETURN 'illegal side-to-move!'; -- ! in returnvalue signals an error
   END IF;
   sla :=INSTR(HJ_FEN_EPD,' ');
   IF sla<>2 THEN RETURN 'space issue ('||sla||'<>2)!'; END IF;-- ! in returnvalue signals an error
   HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+1);
   sla :=INSTR(HJ_FEN_EPD,' ');
   IF sla not in (2,3,4,5) THEN RETURN 'space issue ('||sla||')!'; END IF;-- ! in returnvalue signals an error
   --<Castling ability> 
   hj_lin := substr(HJ_FEN_EPD,1,sla-1);
   IF INSTR(hj_lin,'K') > 0 THEN --white king-side
     HJ_STR := REPLACE(HJ_STR,'k','m');
     HJ_STR := SUBSTR(HJ_STR,1,63)||'r'||SUBSTR(HJ_STR,65);
   END IF;
   IF INSTR(hj_lin,'Q') > 0 THEN --white queen-side
     HJ_STR := REPLACE(HJ_STR,'k','m');
     HJ_STR := SUBSTR(HJ_STR,1,56)||'r'||SUBSTR(HJ_STR,58);
   END IF;
   IF INSTR(hj_lin,'k') > 0 THEN --black king-side
     HJ_STR := REPLACE(HJ_STR,'K','M');
     HJ_STR := SUBSTR(HJ_STR,1,7)||'R'||SUBSTR(HJ_STR,9);
   END IF;
   IF INSTR(hj_lin,'q') > 0 THEN --black queen-side
     HJ_STR := REPLACE(HJ_STR,'K','M');
     HJ_STR := 'R'||SUBSTR(HJ_STR,2);
   END IF;
   HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+1);
   --<En passant target square> 
   IF substr(HJ_FEN_EPD,1,1) <> '-' THEN
     IF substr(HJ_FEN_EPD,2,1) = '3' THEN --white
         sla := 32;
         ep  := 'e';
     ELSIF substr(HJ_FEN_EPD,2,1) = '6' THEN --black   
         sla := 8;
         ep  := 'E';
     ELSE
       RETURN 'illegal en-passant!'; -- ! in returnvalue signals an error
     END IF; 
     sla := sla + ASCII(substr(HJ_FEN_EPD,1,1))-96;
     HJ_STR := SUBSTR(HJ_STR,1,sla-1)||ep||SUBSTR(HJ_STR,sla+1);
   END IF;
   sla :=INSTR(HJ_FEN_EPD,' ');
   HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+1);
   --
   --WRT('EPD: '||HJ_FEN_EPD);
   -- Read of EPD operations to global variables:
   EPD_BESTMOVE      := '';
   EPD_SECONDARYMOVE := '';
   EPD_AVOIDMOVE     := '';   
   EPD_ID            := ''; 
   EPD_COMMENT0      := ''; 
   FOR cnt IN 1..10 LOOP -- scan some operations (normally just 3-4 used):
     IF substr(HJ_FEN_EPD,1,3)='bm ' THEN --best move (example:Rxf7+; )
        sla :=INSTR(HJ_FEN_EPD,';');
        EPD_BESTMOVE := substr(HJ_FEN_EPD,4,sla-4);
        HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+2);
     END IF;
     IF substr(HJ_FEN_EPD,1,3)='sm ' THEN --secondary move
        sla :=INSTR(HJ_FEN_EPD,';');
        EPD_SECONDARYMOVE := substr(HJ_FEN_EPD,4,sla-4);
        HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+2);
     END IF;
     IF substr(HJ_FEN_EPD,1,3)='am ' THEN --avoid move
        sla :=INSTR(HJ_FEN_EPD,';');
        EPD_AVOIDMOVE := substr(HJ_FEN_EPD,4,sla-4);
        HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+2);
     END IF;
     IF substr(HJ_FEN_EPD,1,4)='id "' THEN --id (in "")
        sla :=INSTR(HJ_FEN_EPD,'";');
        EPD_ID := substr(HJ_FEN_EPD,5,sla-5);
        HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+3);
     END IF;
     IF substr(HJ_FEN_EPD,1,4)='c0 "' THEN --comment (in "")
        sla :=INSTR(HJ_FEN_EPD,'";');
        EPD_COMMENT0 := substr(HJ_FEN_EPD,5,sla-5);
        HJ_FEN_EPD := substr(HJ_FEN_EPD,sla+3);
     END IF;
   END LOOP;
   RETURN HJ_STR;
EXCEPTION
  WHEN OTHERS THEN
     RETURN 'FEN_EPD_TO_STR! '||HJ_FEN_EPD||' '||SLA; -- ! in returnvalue signals an error
END FEN_EPD_TO_STR;
--
-- All EPD operations:
--
--    OPERATION       DESCRIPTION  
--    acd             analysis count depth [3]
--    acn             analysis count nodes
--    acs             analysis count seconds
--    am              avoid move(s)
--    bm              best move(s)
--    c0              comment (primary, also c1 though c9)
--    ce              centipawn evaluation
--    dm              direct mate fullmove count
--    draw_accept     accept a draw offer
--    draw_claim      claim a draw
--    draw_offer      offer a draw
--    draw_reject     reject a draw offer
--    eco             Encyclopedia of Chess Openings opening code
--    fmvn            fullmove number
--    hmvc            halfmove clock
--    id              position identification
--    nic             New In Chess opening code
--    noop            no operation
--    pm              predicted move
--    pv              predicted variation
--    rc              repetition count
--    resign          game resignation
--    sm              supplied move
--    tcgs            telecommunication game selector
--    tcri            telecommunication receiver identification
--    tcsi            telecommunication sender identification
--    v0              variation name (primary, also v1 though v9)
    
PROCEDURE still(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, p_st char DEFAULT '') IS  
  x  SIMPLE_INTEGER :=0; 
  xn SIMPLE_INTEGER :=0; 
  y  SIMPLE_INTEGER :=0;
  st char(65);--str65 
BEGIN
  IF p_st is null THEN --set the start-position:
    st:='RSLDMLSRBBBBBBBB                                bbbbbbbbrsldmlsrH';
  ELSIF INSTR(p_st,'/') between 2 and 9 THEN-- standard FEN or EPD format candidate detected
    -- so convert to internal format:
    st := FEN_EPD_TO_STR(p_st);
    IF INSTR(st,'!') > 0 THEN -- Conversion failed, so st contains the error-details
      RAISE_APPLICATION_ERROR(-20001, 'FEN_EPD_TO_STR failed (not legal FEN or EPD position): '||st);
    END IF;
  ELSE
    IF instr(p_st,-1) in ('W','B') THEN -- internal format candidate, but english
      st := TRANSLATE(SUBSTR(p_st,1,64),'PpBbNnQqRrCc',
                                        'BbLlSsDdTtRr');
      IF instr(p_st,-1) = 'W' THEN
        st := st||'H';                               
      ELSE
        st := st||'S';   
      END IF;                            
    ELSE
      st := p_st;
    END IF;
  END IF;
  FOR x IN -10..109 LOOP 
    stilling(stOff+ x):=edge; 
  END LOOP;
  FOR y IN 1..8 LOOP 
    FOR x IN 1..8 LOOP 
      stilling(stOff+ x+10*y):=ASCII(substr(st,(8-y)*8+x,1));
    END LOOP;
  END LOOP;
  stilling(stOff+ HvisTur):=ASCII(substr(st,65,1));
END still;


















































PROCEDURE GetNextTil(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, fra in out SIMPLE_INTEGER ,til in out SIMPLE_INTEGER, retning IN OUT SIMPLE_INTEGER,
                     MoveTyp in out MOVETYPE) IS
-- finder s/h næste træk med nuværende brik, til=fra -> til=89 når ikke flere
-- !!!!!!!!!! slag for enpassant markeres IKKE for sort, bør laves
  Done BOOLEAN;
  Brik SIMPLE_INTEGER:=0; 
  Maxx SIMPLE_INTEGER:=0; 
  just  SIMPLE_INTEGER:=0;
  hvid BOOLEAN; Max1 BOOLEAN;BondeH BOOLEAN;BondeS BOOLEAN;
BEGIN
  hvid:=stilling(stOff+ HvisTur)=wT;
  Brik:=stilling(stOff+ fra);
  Maxx :=retn(rxOff+ Brik) (ryOff+ MaxDistance);
  Max1:=Maxx=1;
  IF retning=0 THEN retning := retn(rxOff+ Brik) (ryOff+ retning); END IF;
  Done:=FALSE;
  BondeH:= Brik=wP;
  BondeS:= Brik=bP;
  LOOP
    IF hvid THEN

      -- adjust when under-promotion
      IF BondeH AND (retning<0) THEN
        just:=20;
        WHILE retning+just<9 LOOP
          just:=just+10;
        END LOOP;
      ELSE
        just:=0;
      END IF;
      -- next retning if :
      --   Max or occupied field reached,
      --   reached the edge,
      --   or own piece 
      ---WRT('GetNextTil '||fra||til||' "'||retning||'" '||just);
      IF (fra<>til) AND (Max1 OR (stilling(stOff+ til)<>spc))
      OR (stilling(stOff+ til+retning)=edge)
      OR (stilling(stOff+ til+retning+just)>wA) THEN
        IF BondeH AND (fra<71) AND (retning=20) THEN -- so skip under-promotions
          retning:=0;
        ELSE
          retning:=retn(rxOff+ Brik) (ryOff+ retning);
        END IF; 
        til:=fra;
        IF retning=0 THEN
          Done:=TRUE;
          til:=89;
        END IF;
      ELSE
        til:=til+retning;

        just:=0;      
        IF BondeH THEN
          IF til<fra THEN -- adjust when under-promotion
            just:=20;
            WHILE til+just-fra<9 LOOP
              just:=just+10;
            END LOOP;
            IF stilling(stOff+ til+just)<>spc THEN
              MoveTyp:=MOVEslag;
            ELSE
              MoveTyp:=MOVEnormal;
            END IF;
          ELSE
            IF stilling(stOff+ til)<>spc THEN
              MoveTyp:=MOVEslag;
            ELSE
              IF BondeH AND (stilling(stOff+ til-10)=bE) THEN
                MoveTyp:=MOVEslag;
              ELSE
                MoveTyp:=MOVEnormal;
              END IF;
            END IF;
          END IF;
        ELSE
          IF stilling(stOff+ til)<>spc THEN
            MoveTyp:=MOVEslag;
          ELSE
            MoveTyp:=MOVEnormal;
          END IF;
        END IF;
        IF BondeH THEN -- Pawn
          CASE 
            WHEN retning in (-30,-20,-10,10) THEN Done := (stilling(stOff+ til+just)=spc);
            WHEN retning in (-31,-29,-21,-19,-11,-9,9,11) THEN
              IF stilling(stOff+ til+just)<>spc THEN
                Done:=TRUE;
              ELSE
                Done:=stilling(stOff+ til-10)=bE;
                SET_INCL(MoveTyp,MOVEenpassant);
              END IF;
            WHEN retning = 20   THEN Done := (fra>=21) AND (fra<=28) AND (stilling(stOff+ til-10)=spc)
                     AND (stilling(stOff+ til)=spc);
          ELSE 
            NULL;
          END CASE;
        ELSE -- not a pawn 
          IF ABS(retning)=2 THEN  -- is 2 only when castling
            SET_INCL(MoveTyp,MOVErokade);
            IF retning=2 THEN  -- O-O
              Done:=(stilling(stOff+ 16)=spc) AND (stilling(stOff+ 17)=spc)
              AND (stilling(stOff+ 18)=wC);
            ELSE    -- O-O-O
              Done:=(stilling(stOff+ 14)=spc) AND (stilling(stOff+ 13)=spc)
              AND (stilling(stOff+ 12)=spc) AND (stilling(stOff+ 11)=wC);
            END IF;
          ELSE 
            Done:=TRUE;
          END IF;
        END IF;
      END IF;
    ELSE -- for black

      -- adjust when under-promotion
      IF BondeS AND (retning>0) THEN
        just:=-20;
        WHILE retning+just>-9 LOOP
          just:=just-10;
        END LOOP;
      ELSE
        just:=0;
      END IF;

      -- next retning if :
      --   Max or occupied field is reached, edge or own piece reached
      IF  (fra<>til) AND ( Max1 OR (stilling(stOff+ til)<>spc))
      OR (stilling(stOff+ til+retning)=edge)
      OR (stilling(stOff+ til+retning+just)>spc) AND (stilling(stOff+ til+retning+just)<wA) THEN
        IF BondeS AND (fra>28) AND (retning=-20) THEN -- skip under-promotions
          retning:=0;
        ELSE
          retning:=retn(rxOff+ Brik) (ryOff+ retning);
        END IF; 
        til:=fra;
        IF retning=0 THEN
          Done:=TRUE;
          til:=89;
        END IF;
      ELSE
        til:=til+retning;

        -- adjust if under-promotion
        IF BondeS AND (til>fra) THEN
          just:=-20;
          WHILE fra-til-just<9 LOOP
            just:=just-10;
          END LOOP;
        ELSE
          just:=0;
        END IF;

        IF stilling(stOff+ til+just)<>spc THEN
          MoveTyp:=MOVEslag;
        ELSE
          MoveTyp:=MOVEnormal;
        END IF;
        IF BondeS THEN -- Pawn
          CASE
             WHEN retning IN (30,20,10,-10)   THEN Done := (stilling(stOff+ til+just)=spc);
             WHEN retning IN (31,29,21,19,11,9,-9,-11) THEN 
              IF stilling(stOff+ til+just)<>spc THEN
                Done:=TRUE;
              ELSE
                Done:=stilling(stOff+ til+just+10)=wE;
                SET_INCL(MoveTyp,MOVEenpassant);
              END IF;
            WHEN retning = -20   THEN Done := (fra>=71) AND (fra<=78) AND (stilling(stOff+ til+10)=spc)
                       AND (stilling(stOff+ til)=spc);
          ELSE 
            NULL;
          END CASE;
        ELSE -- not a pawn
          IF ABS(retning)=2 THEN  -- 2 only when castling
            SET_INCL(MoveTyp,MOVErokade);
            IF retning=2 THEN  -- O-O
              Done:=(stilling(stOff+ 86)=spc) AND (stilling(stOff+ 87)=spc)
              AND (stilling(stOff+ 88)=bC);
            ELSE    -- O-O-O
              Done:=(stilling(stOff+ 84)=spc) AND (stilling(stOff+ 83)=spc)
              AND (stilling(stOff+ 82)=spc) AND (stilling(stOff+ 81)=bC);
            END IF;
          ELSE 
            Done:=TRUE;
          END IF;
        END IF;
      END IF;
    END IF;
    EXIT WHEN Done;
  END LOOP;
END GetNextTil;

PROCEDURE DoMove(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, fra SIMPLE_INTEGER,til SIMPLE_INTEGER, MoveTyp MOVETYPE) IS
-- udfører (Hvidt/Sort) træk, der i forvejen er valideret OK 
-- MoveTyp skal være defineret (og ændres ikke her) 
  n SIMPLE_INTEGER :=0;
BEGIN
  IF stilling(stOff+ HvisTur)=wT THEN
    CASE 
      WHEN stilling(stOff+ fra) = wP  THEN
        IF fra>70 THEN 
          CASE 
            WHEN til-fra IN(  9, 10, 11) THEN stilling(stOff+ til)   :=wQ; -- bondeforvandling to queen (dronning) 
            WHEN til-fra IN(-11,-10, -9) THEN stilling(stOff+ til+20):=wR; -- for lav til=>underforvandl
            WHEN til-fra IN(-21,-20,-19) THEN stilling(stOff+ til+30):=wN;
            WHEN til-fra IN(-31,-30,-29) THEN stilling(stOff+ til+40):=wB;
          END CASE;
        ELSE
          IF (til-fra=20) AND ((stilling(stOff+ til-1)=bP) OR (stilling(stOff+ til+1)=bP)) THEN
            stilling(stOff+ til):=wE; -- set en-passant possible
          ELSE
            stilling(stOff+ til):=stilling(stOff+ fra);
          END IF;
        END IF;
      WHEN stilling(stOff+ fra) = wC  THEN 
               stilling(stOff+ til):=wR;        -- fjern tårns rokaderet 
               -- hvis også andet tårn har været flyttet så fjern konges rokaderet 
               IF ((fra=11) AND (stilling(stOff+ 18)<>wC) OR (fra=18) AND (stilling(stOff+ 11)<>wC)) 
               AND (stilling(stOff+ 15)=wM) THEN stilling(stOff+ 15):=wK; END IF;
      WHEN stilling(stOff+ fra) = wM THEN 
               stilling(stOff+ til):=wK;        -- fjern konges rokaderet 
               IF stilling(stOff+ 11)=wC THEN stilling(stOff+ 11):=wR; END IF;
               IF stilling(stOff+ 18)=wC THEN stilling(stOff+ 18):=wR; END IF;
    ELSE   
      stilling(stOff+ til):=stilling(stOff+ fra);
    END CASE;
    stilling(stOff+ fra):=spc;
    IF SET_IN(MOVEenpassant,MoveTyp) THEN
      stilling(stOff+ til-10):=spc;      -- remove e.p. pawn (bonde) 
    ELSIF SET_IN(MOVErokade,MoveTyp) THEN
      IF til<fra THEN             -- move/convert rook (tårn) 
        stilling(stOff+ 14):=wR;
        stilling(stOff+ 11):=spc;
        IF stilling(stOff+ 18)=wC THEN stilling(stOff+ 18):=wR; END IF;
      ELSE
        stilling(stOff+ 16):=wR;
        stilling(stOff+ 18):=spc;
        IF stilling(stOff+ 11)=wC THEN stilling(stOff+ 11):=wR; END IF;
      END IF;
    END IF;
    FOR n IN 51..58 LOOP
      IF stilling(stOff+ n)=bE THEN stilling(stOff+ n):=bP; END IF;  -- remove evt. e.p. possibility. 
    END LOOP;
    stilling(stOff+ HvisTur):=bT;
  ELSE
    CASE
      WHEN stilling(stOff+ fra) = bP  THEN
        IF fra<29 THEN
          CASE
             WHEN fra-til IN (  9, 10, 11) THEN stilling(stOff+ til)   :=bQ;-- pawn promotion to queen (dronning)
             WHEN fra-til IN (-11,-10, -9) THEN stilling(stOff+ til-20):=bR;-- too low til=>underpromotion
             WHEN fra-til IN (-21,-20,-19) THEN stilling(stOff+ til-30):=bN;-- and adjust down
             WHEN fra-til IN (-31,-30,-29) THEN stilling(stOff+ til-40):=bB;
          END CASE;
        ELSE
          IF (fra-til=20) AND ((stilling(stOff+ til+1)=wP) OR (stilling(stOff+ til-1)=wP)) THEN
            stilling(stOff+ til):=bE; -- set en-passant possible
          ELSE
            stilling(stOff+ til):=stilling(stOff+ fra);
          END IF;
        END IF;
      WHEN stilling(stOff+ fra) = bC  THEN 
               stilling(stOff+ til):=bR;        -- remove rook (tårns) castling right
               IF ((fra=81) AND (stilling(stOff+ 88)<>bC) OR (fra=88) AND (stilling(stOff+ 81)<>bC)) AND (stilling(stOff+ 85)=bM) THEN --!!!!!!!!!!!!!
                 stilling(stOff+ 85):=bK;
               END IF;
      WHEN stilling(stOff+ fra) = bM  THEN 
               stilling(stOff+ til):=bK;        -- remove King (tårns) castling right
               IF stilling(stOff+ 81)=bC THEN stilling(stOff+ 81):=bR; END IF;
               IF stilling(stOff+ 88)=bC THEN stilling(stOff+ 88):=bR; END IF;
    ELSE   
      stilling(stOff+ til):=stilling(stOff+ fra);
    END CASE;
    stilling(stOff+ fra):=spc;
    IF SET_IN(MOVEenpassant,MoveTyp) THEN
      stilling(stOff+ til+10):=spc;      -- remove e.p. pawn
    ELSIF SET_IN(MOVErokade,MoveTyp) THEN
      IF til<fra THEN             -- move/convert rook (tårn)
        stilling(stOff+ 84):=bR;
        stilling(stOff+ 81):=spc;
        IF stilling(stOff+ 88)=bC THEN stilling(stOff+ 88):=bR; END IF;
      ELSE
        stilling(stOff+ 86):=bR;
        stilling(stOff+ 88):=spc;
        IF stilling(stOff+ 81)=bC THEN stilling(stOff+ 81):=bR; END IF;
      END IF;
    END IF;
    FOR n IN 41..48 LOOP 
      IF stilling(stOff+ n)=wE THEN stilling(stOff+ n):=wP; END IF;  -- remove e.p. possibility
    END LOOP;
    stilling(stOff+ HvisTur):=wT;
  END IF;
--Vis('Efter DoMove:',stilling);
END DoMove;

PROCEDURE DoMoveC(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, fra SIMPLE_INTEGER,til SIMPLE_INTEGER) IS
-- udfører (Hvidt/Sort) træk, der i forvejen er valideret OK
-- som DoMove, men kræver IKKE MoveTyp information
-- Hurtigere end DoMoveOK når træk ER valideret OK
  MoveTyp MOVETYPE := MOVEnormal;
BEGIN
  IF stilling(stOff+ til)=spc THEN
    MoveTyp:=MOVEnormal;
  ELSE
    MoveTyp:=MOVEslag;
  END IF;
  IF stilling(stOff+ HvisTur)=wT THEN
    IF (stilling(stOff+ fra)=wP) 
    AND  ((til-fra=9) OR (til-fra=11))
    AND  (stilling(stOff+ til)=spc) THEN
      SET_INCL(MoveTyp,MOVEenpassant);
    END IF;
    IF (stilling(stOff+ fra)=wM)
    AND  (ABS(til-fra)=2) THEN
      SET_INCL(MoveTyp,MOVErokade);
    END IF;
  ELSE
    IF (stilling(stOff+ fra)=bP) 
    AND  ((fra-til=9) OR (fra-til=11))
    AND  (stilling(stOff+ til)=spc) THEN
      SET_INCL(MoveTyp,MOVEenpassant);
    END IF;
    IF (stilling(stOff+ fra)=bM)
    AND  (ABS(til-fra)=2) THEN
      SET_INCL(MoveTyp,MOVErokade);
    END IF;
  END IF;
  DoMove(stilling,fra,til,MoveTyp);
END DoMoveC;


FUNCTION CheckSkak2(stilling IN OUT PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, n SIMPLE_INTEGER, hvid BOOLEAN) RETURN BOOLEAN IS
-- checker om felt n er truet af sort/hvid
  retning SIMPLE_INTEGER:=0;
  tst SIMPLE_INTEGER:=0;
  cnt SIMPLE_INTEGER:=0;
  skak BOOLEAN;
BEGIN
  IF hvid THEN -- White check
    skak:=(stilling(stOff+ n-21)=bN) OR (stilling(stOff+ n-19)=bN) OR (stilling(stOff+ n-12)=bN)
    OR (stilling(stOff+ n- 8)=bN) OR (stilling(stOff+ n+ 8)=bN) OR (stilling(stOff+ n+12)=bN)
    OR (stilling(stOff+ n+19)=bN) OR (stilling(stOff+ n+21)=bN);
    retning:=retn(rxOff+ wR) (ryOff+ 0);       -- look in all rook (tårn) directions
    LOOP
      tst:=n;
      cnt:=0;
      LOOP                    -- find first ccupied field in the direction
        tst:=tst+retning;
        cnt := cnt + 1;
        exit when stilling(stOff+ tst)<>spc;
      END LOOP;
      IF (stilling(stOff+ tst)=bQ) OR (stilling(stOff+ tst)=bR) OR (stilling(stOff+ tst)=bC) THEN
        skak:=TRUE;
      ELSIF (cnt=1) AND ((stilling(stOff+ tst)=bK) OR (stilling(stOff+ tst)=bM)) THEN
        skak:=TRUE;
      END IF;
      retning:=retn(rxOff+ wR) (ryOff+ retning);
      exit when (retning=0) OR skak;
    END LOOP;
    IF NOT skak THEN
      retning:=retn(rxOff+ wB) (ryOff+ 0);       -- look in all bishop (løber) directions
      LOOP
        tst:=n;
        cnt:=0;
        LOOP                  -- find first occupied field in the direction
          tst:=tst+retning;
          cnt := cnt + 1;
          exit when stilling(stOff+ tst)<>spc;
        END LOOP;
        IF (stilling(stOff+ tst)=bQ) OR (stilling(stOff+ tst)=bB) THEN
          skak:=TRUE;
        ELSIF cnt=1 THEN
          IF (stilling(stOff+ tst)=bK) OR (stilling(stOff+ tst)=bM) OR (stilling(stOff+ tst)=bP) AND ((retning=9) OR (retning=11)) THEN
            skak:=TRUE;
          END IF;
        END IF;
        retning:=retn(rxOff+ wB) (ryOff+ retning);
        exit when (retning=0) OR skak;
      END LOOP; 
    END IF;
  ELSE -- black check
    skak:=(stilling(stOff+ n-21)=wN) OR (stilling(stOff+ n-19)=wN) OR (stilling(stOff+ n-12)=wN)
    OR (stilling(stOff+ n- 8)=wN) OR (stilling(stOff+ n+ 8)=wN) OR (stilling(stOff+ n+12)=wN)
    OR (stilling(stOff+ n+19)=wN) OR (stilling(stOff+ n+21)=wN);
    retning:=retn(rxOff+ wR) (ryOff+ 0);       -- led i alle tårn retninger 
    LOOP
      tst:=n;
      cnt:=0;
      LOOP                    -- find første ikke-tomme felt i retningen 
        tst:=tst+retning;
        cnt := cnt + 1;
        EXIT WHEN stilling(stOff+ tst)<>spc;
       END LOOP;
      IF (stilling(stOff+ tst)=wQ) OR (stilling(stOff+ tst)=wR) OR (stilling(stOff+ tst)=wC) THEN
        skak:=TRUE;
      ELSIF (cnt=1) AND ((stilling(stOff+ tst)=wK) OR (stilling(stOff+ tst)=wM)) THEN
        skak:=TRUE;
      END IF;
      retning:=retn(rxOff+ wR) (ryOff+ retning);
      EXIT WHEN (retning=0) OR skak;
    END LOOP;
    IF NOT skak THEN
      retning:=retn(rxOff+ wB) (ryOff+ 0);       -- led i alle løber retninger 
      LOOP
        tst:=n;
        cnt:=0;
        LOOP                    -- find første ikke-tomme felt i retningen 
          tst:=tst+retning;
          cnt := cnt + 1;
          EXIT WHEN stilling(stOff+ tst)<>spc;
        END LOOP; 
        IF (stilling(stOff+ tst)=wQ) OR (stilling(stOff+ tst)=wB) THEN
          skak:=TRUE;
        ELSIF cnt=1 THEN
          IF (stilling(stOff+ tst)=wK) OR (stilling(stOff+ tst)=wM) OR (stilling(stOff+ tst)=wP) AND ((retning=-9) OR (retning=-11)) THEN
            skak:=TRUE;
          END IF;
        END IF;
        retning:=retn(rxOff+ wB) (ryOff+ retning);
        EXIT WHEN (retning=0) OR skak;
      END LOOP; 
    END IF;
  END IF;
  RETURN(skak);
END CheckSkak2;

--$ ENDIF

FUNCTION CheckSkak(stilling IN OUT PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, n SIMPLE_INTEGER, hvid BOOLEAN) RETURN BOOLEAN IS
-- checker om felt n er truet af sort/hvid
  retning SIMPLE_INTEGER:=0;
  tst SIMPLE_INTEGER:=0;
  cnt SIMPLE_INTEGER:=0;
BEGIN
  IF hvid THEN -- Hvid check !!
    IF (stilling(stOff+ n-21)=bN) OR (stilling(stOff+ n-19)=bN) OR (stilling(stOff+ n-12)=bN)
    OR (stilling(stOff+ n- 8)=bN) OR (stilling(stOff+ n+ 8)=bN) OR (stilling(stOff+ n+12)=bN)
    OR (stilling(stOff+ n+19)=bN) OR (stilling(stOff+ n+21)=bN) THEN
      RETURN(TRUE);
    ELSE
      retning:=retn(rxOff+ wQ) (ryOff+ 0);       -- led i alle otte retninger 
      LOOP
        tst:=n;
        cnt:=0;
        LOOP                    -- find første ikke-tomme felt i retningen 
          tst:=tst+retning;
          cnt := cnt + 1;
          EXIT WHEN stilling(stOff+ tst)<>spc;
        END LOOP; 
        CASE     -- check om den fundne brik giver skak 
          WHEN stilling(stOff+ tst) = bQ       THEN RETURN(TRUE);
          WHEN stilling(stOff+ tst) =  bB      THEN CASE
                                                WHEN retning in (-11,-9,9,11) THEN RETURN(TRUE);
                                                ELSE NULL; 
                                              END CASE;
          WHEN stilling(stOff+ tst) in(bR,bC) THEN CASE
                                                WHEN retning in ( -10,-1,1,10) THEN RETURN(TRUE);
                                                ELSE NULL; 
                                              END CASE;
          WHEN stilling(stOff+ tst) in(bK,bM) THEN IF cnt=1 THEN RETURN(TRUE); END IF;
          WHEN stilling(stOff+ tst) =  bP      THEN IF (cnt=1) AND ((retning=9) OR (retning=11)) THEN RETURN(TRUE); END IF;
        ELSE 
          NULL;
        END CASE;
        retning:=retn(rxOff+ wQ) (ryOff+ retning);
        EXIT WHEN (retning=0);
      END LOOP; 
    END IF;
    RETURN(FALSE);
  ELSE -- sort check
    IF (stilling(stOff+ n-21)=wN) OR (stilling(stOff+ n-19)=wN) OR (stilling(stOff+ n-12)=wN)
    OR (stilling(stOff+ n- 8)=wN) OR (stilling(stOff+ n+ 8)=wN) OR (stilling(stOff+ n+12)=wN)
    OR (stilling(stOff+ n+19)=wN) OR (stilling(stOff+ n+21)=wN) THEN
      RETURN(TRUE);
    ELSE
      retning:=retn(rxOff+ wQ) (ryOff+ 0);       -- led i alle otte retninger 
      LOOP
        tst:=n;
        cnt:=0;
        LOOP                    -- find første ikke-tomme felt i retningen 
          tst:=tst+retning;
          cnt := cnt + 1;
          EXIT WHEN stilling(stOff+ tst)<>spc;
        END LOOP; 
        CASE    -- check om den fundne brik giver skak 
          WHEN stilling(stOff+ tst) = wQ     THEN RETURN(TRUE);
          WHEN stilling(stOff+ tst) = wB     THEN CASE
                             WHEN retning in(-11,-9,9,11) THEN RETURN(TRUE);
                             ELSE NULL; END CASE;
          WHEN stilling(stOff+ tst) in( wR,wC) THEN CASE 
                             WHEN retning in( -10,-1,1,10) THEN RETURN(TRUE);
                                ELSE NULL; END CASE;
          WHEN stilling(stOff+ tst) in( wK,wM) THEN IF cnt=1 THEN RETURN(TRUE); END IF;
          WHEN stilling(stOff+ tst) = wP     THEN IF (cnt=1) AND ((retning=-9) OR (retning=-11)) THEN RETURN(TRUE); END IF;
          ELSE NULL; 
        END CASE;
        retning:=retn(rxOff+ wQ) (ryOff+ retning);
        EXIT WHEN (retning=0);
      END LOOP; 
    END IF;
    RETURN(FALSE);
  END IF;
END CheckSkak;

FUNCTION IkkeSkak(stilling IN OUT PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, fra SIMPLE_INTEGER,p_til SIMPLE_INTEGER,
                  MoveTyp MOVETYPE) RETURN BOOLEAN IS
-- checker om (hvidt/sort) træk er ulovligt p.gr.a. at kongen er skak 
-- eller rokerer fra/over truet felt 
-- kræver at MoveTyp er sat korrekt når rokade og pat 
  skak BOOLEAN;
  n SIMPLE_INTEGER:=0;
  vej SIMPLE_INTEGER:=0;
  cfra SIMPLE_INTEGER:=0;
  ctil SIMPLE_INTEGER:=0;
  hvid BOOLEAN;
  til SIMPLE_INTEGER:=p_til; 
BEGIN
  hvid:=stilling(stOff+ HvisTur)=wT;
  IF SET_IN(MOVErokade,MoveTyp) THEN
    skak:=CheckSkak(stilling,fra,hvid); -- rokeres FRA truet felt ? 
    IF NOT skak THEN
      IF til<fra THEN vej:=-1; ELSE vej:=1; END IF;
      skak:=CheckSkak(stilling,fra+vej,hvid);  -- rokeres OVER truet felt ? 
      IF NOT skak THEN
        cfra:=stilling(stOff+ fra);
        stilling(stOff+ fra):=spc;
        skak:=CheckSkak(stilling,til,hvid);    -- rokeres TIL truet felt ? 
        stilling(stOff+ fra):=cfra;
      END IF;
    END IF;
  ELSE

    IF SET_IN(MOVEpat,MoveTyp) THEN
      RETURN(FALSE);
    END IF;

    IF hvid THEN
      cfra:=stilling(stOff+ fra);
      IF (cfra=wP) AND (fra>70) AND (til<fra) THEN
        til:=til+20;
        WHILE til<fra LOOP
          til:=til+10;
        END LOOP;
      END IF;       
      ctil:=stilling(stOff+ til);
      stilling(stOff+ til):=cfra;
      stilling(stOff+ fra):=spc;
      IF stilling(stOff+ 15)=wM THEN
        skak:=CheckSkak(stilling,15,hvid) ;
      ELSIF stilling(stOff+ 17)=wK THEN
        skak:=CheckSkak(stilling,17,hvid);
      ELSE
        n:=11;         -- find konge
        WHILE (stilling(stOff+ n)<>wK) AND (stilling(stOff+ n)<>wM) AND (n<89) LOOP n := n + 1; END LOOP;
        IF n<89 THEN
          skak:=CheckSkak(stilling,n,hvid);
        ELSE skak:=FALSE; END IF; -- er kongen skak?
      END IF;
      stilling(stOff+ fra):=cfra;
      stilling(stOff+ til):=ctil;
    ELSE
      cfra:=stilling(stOff+ fra);
      IF (cfra=bP) AND (fra<29) AND (til>fra) THEN
        til:=til-20;
        WHILE til>fra LOOP
          til:=til-10;
        END LOOP;
      END IF;       
      ctil:=stilling(stOff+ til);
      stilling(stOff+ til):=cfra;
      stilling(stOff+ fra):=spc;
      IF stilling(stOff+ 85)=bM THEN
        skak:=CheckSkak(stilling,85,hvid) ;
      ELSIF stilling(stOff+ 87)=bK THEN
        skak:=CheckSkak(stilling,87,hvid);
      ELSE
        n:=88;
        WHILE (stilling(stOff+ n)<>bK) AND (stilling(stOff+ n)<>bM) AND (n>10) LOOP n := n - 1; END LOOP;
        IF n>10 THEN
          skak:=CheckSkak(stilling,n,hvid);
        ELSE 
          skak:=FALSE;
        END IF; -- er kongen skak?
      END IF;
      stilling(stOff+ fra):=cfra;
      stilling(stOff+ til):=ctil;
    END IF;
  END IF;
  RETURN(NOT skak);
END IkkeSkak;

PROCEDURE GetNext(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, 
                  fra in out SIMPLE_INTEGER,
                  til in out SIMPLE_INTEGER,
                  retning in out SIMPLE_INTEGER,
                  MoveTyp in out MOVETYPE) IS
-- finder næste (hvide/sorte) træk i stillingen, fra=89 når ikke flere
  hvid BOOLEAN;
BEGIN
  IF stilling(stOff+ HvisTur)=wT THEN
    LOOP
      LOOP
        IF til>88 THEN
          LOOP -- find næste hvide brik
            fra := fra + 1;
            EXIT WHEN (fra>88) OR (stilling(stOff+ fra)>wA);
          END LOOP; 
          til:=fra;
          retning:=0;
        END IF;
        IF fra<>89 THEN GetNextTil(stilling,fra,til,retning,MoveTyp); END IF;
        EXIT WHEN (til<>89) OR (fra=89);
      END LOOP; 
      EXIT WHEN (fra=89) OR IkkeSkak(stilling,fra,til,MoveTyp);
    END LOOP; 
  ELSE -- sort
    LOOP
      LOOP
        IF til>88 THEN
          LOOP
            fra := fra + 1;
            EXIT WHEN (fra>88) OR (stilling(stOff+ fra)>bA) AND (stilling(stOff+ fra)<wA);
          END LOOP; 
          til:=fra;
          retning:=0;
        END IF;
        IF fra<>89 THEN GetNextTil(stilling,fra,til,retning,MoveTyp); END IF;
        EXIT WHEN (til<>89) OR (fra=89);
      END LOOP; 
      EXIT WHEN (fra=89) OR IkkeSkak(stilling,fra,til,MoveTyp);
    END LOOP; 
  END IF;
--WRITELN(s('Getnext exit: ')+l(fra)+s('-')+l(til)+s(' retn:')+l(retning));
END GetNext;

PROCEDURE Mirror(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE) IS
n SIMPLE_INTEGER:=0;
m SIMPLE_INTEGER:=0;
nm SIMPLE_INTEGER:=0;
om SIMPLE_INTEGER:=0;
ch SIMPLE_INTEGER:=0;
ch2 SIMPLE_INTEGER:=0;
BEGIN
IF stilling(stOff+ HvisTur)=bT THEN 
  stilling(stOff+ HvisTur):=wT;
ELSE 
  stilling(stOff+ HvisTur):=bT;
END IF;
FOR n IN 1..4 LOOP 
  nm:=10*n;
  om:=90-nm;
  FOR m IN 1..8 LOOP
    nm := nm + 1;
    om := om + 1;
    ch:=stilling(stOff+ nm);
    IF ch>wA THEN
      ch := ch - 32;
    ELSIF ch>bA THEN
      ch := ch + 32;
    END IF;
    ch2:=stilling(stOff+ om);
    IF ch2>wA THEN 
      ch2 := ch2 - 32;
    ELSIF ch2>bA THEN
      ch2 := ch2 + 32;
    END IF;
    stilling(stOff+ nm):=ch2; 
    stilling(stOff+ om):=ch;
  END LOOP;
END LOOP;
END Mirror;
--
--
--
--
FUNCTION DoMoveOk(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, fra SIMPLE_INTEGER,til SIMPLE_INTEGER,MoveTyp in out MOVETYPE) RETURN BOOLEAN IS
-- fuldstændigt check af om (s/h) træk er ok, genererer sort/hvide træk med DoMove
-- IF not DoMoveOk() then fejl.. -> udfører et træk hvis det er lovligt
  fr SIMPLE_INTEGER:=0;
  ti SIMPLE_INTEGER:=0;
  retning SIMPLE_INTEGER:=0;
  black BOOLEAN; 
  DoMoveOkh BOOLEAN;
BEGIN
  fr:=fra-1;
  ti:=89;
  LOOP
    GetNext(stilling, fr,ti, retning, MoveTyp);
--WRITELN(s('I DoMoveOk, Efter GetNext: fr=')+l(fr)+s(' fra=')+l(fra));
    EXIT WHEN (ti=til) OR (fr>fra);
  END LOOP; 
  IF fr>fra THEN
--WRITELN(s('Efter GetNext: OKh=0 fr=')+l(fr)+s(' fra=')+l(fra));
    DoMoveOkh:=FALSE;
  ELSE
    DoMove(stilling,fr,ti,MoveTyp);
    DoMoveOkh:=TRUE;
    TraekNr := TraekNr + 1;
  END IF;
  RETURN(DoMoveOkh);
END DoMoveOk;
--
--
PROCEDURE ShellSort_ (Trk in out TRAEKDATA, Upto SIMPLE_INTEGER) IS
  i SIMPLE_INTEGER:=0;
  j SIMPLE_INTEGER:=0; 
  stepp SIMPLE_INTEGER:=0;
  tmp   TRKDATA;
Begin
  stepp:=FLOOR(Upto/2);
  While stepp>0 LOOP
    For i in stepp..Upto-1 LOOP
      tmp:=Trk (1+ i);
      j:=i;
      While (j>=stepp) and (Trk(1+ j-stepp).Vlu < tmp.Vlu) LOOP
        Trk(1+ j):=Trk(1+ j-stepp);
        j:=j-stepp;
      End LOOP;
      Trk(1+ j):=tmp;
    End LOOP;
    stepp:=FLOOR(stepp/2);
  End LOOP;
End ShellSort_;
--
PROCEDURE QSortTrk(Trk in out TRAEKDATA, Fromm SIMPLE_INTEGER,Upto SIMPLE_INTEGER) IS
  swp TRKDATA;
  i SIMPLE_INTEGER:=0;
  j SIMPLE_INTEGER:=0;
  dh SIMPLE_INTEGER:=0;
  ih SIMPLE_INTEGER:=0;
BEGIN
  IF Upto-Fromm<6 THEN -- use INSERT-SORT on lists 2-6 long
    FOR j in Fromm..Upto-1 LOOP
      ih:=j;
      FOR i in ih+1..Upto LOOP -- Find the greatest
        IF Trk(ih).Vlu<Trk(i).Vlu THEN
          ih:=i;
        END IF;
      END LOOP;
      IF ih<>j THEN -- swap
        swp:=Trk(j);
        Trk(j):=Trk(ih);
        Trk(ih):=swp;
      END IF; 
    END LOOP;
  ELSE -- QUICK-SORT lists longer than 7
    i:=Fromm; 
    j:=Upto; 
    --WRT('QS:'||Fromm||' '||Upto||' '||FLOOR((Fromm+Upto)/2));
    dh:=Trk(FLOOR((Fromm+Upto)/2)).Vlu; -- were DIV (remainder not OK)
    LOOP
      WHILE dh<Trk(i).Vlu LOOP i := i + 1; END LOOP;
      WHILE dh>Trk(j).Vlu LOOP j := j - 1; END LOOP;
      IF i<=j THEN
        swp:=Trk(i);
        Trk(i):=Trk(j);
        Trk(j):=swp;
        i := i + 1;
        j := j - 1;
      END IF;
      EXIT WHEN i > j;
    END LOOP; 
    IF Fromm<j THEN QSortTrk(Trk,Fromm,j); END IF;
    IF i<Upto THEN QSortTrk(Trk,i,Upto); END IF;
  END IF;
END QSortTrk;

-- FirstCountAttacker returns the number for the smallest piece..take back
FUNCTION Egain(stilling IN OUT PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE,
               fr SIMPLE_INTEGER,
               ti SIMPLE_INTEGER,
               OwnCount IN OUT SIMPLE_INTEGER,
               FirstCountAttacker IN OUT SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
  TYPE FIGHTERS IS VARRAY(8) OF SIMPLE_INTEGER;--1..stDcount
  n      SIMPLE_INTEGER :=0;
  risk   SIMPLE_INTEGER :=0;
  ValueC SIMPLE_INTEGER :=0;
  WhF FIGHTERS :=FIGHTERS(0,0,0,0,0,0,0,0); --stDcount
  BlF FIGHTERS :=FIGHTERS(0,0,0,0,0,0,0,0); 
FUNCTION Fight(p_Fown FIGHTERS, Fopp FIGHTERS, Pool SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
  p    SIMPLE_INTEGER:=0; 
  summ SIMPLE_INTEGER:=0; 
  risk SIMPLE_INTEGER:=0;
  Fown FIGHTERS:=p_fown;
BEGIN
  p := stDpawns;
  WHILE Fown(p)=0 LOOP p := p + 1; END LOOP;
  Fown(p) := Fown(p) - 1;
  Fown(stDcount) := Fown(stDcount) - 1;
  risk:=stDarr(p);
--
--CASE
--WHEN p= stDpawns                    THEN risk:= ValueB; 
--WHEN p= stDknights                  THEN risk:= Value_S;
--WHEN p IN (stDbishops,stDbishopsB)  THEN risk:= ValueL;
--WHEN p IN (stDrooks,stDrooksB)      THEN risk:= ValueT;
--WHEN p= stDqueens                   THEN risk:= ValueD;
--WHEN p= stDking                     THEN risk:= ValueK;
--END CASE;
--
  IF Fopp(stDcount)=0 THEN
    summ:=Pool;
  ELSE
    summ:=Pool-Fight(Fopp,Fown,risk);
  END IF;
  IF summ<0 THEN RETURN(0); ELSE RETURN(summ); END IF;
END Fight;
PROCEDURE scan(r SIMPLE_INTEGER,Diag BOOLEAN) IS  --to count queens,rooks,bishops
  n SIMPLE_INTEGER:=0;
  ch_n SIMPLE_INTEGER:=0;
  Black BOOLEAN;
  --ch CHAR(1);
BEGIN
--$ IF FalseWRITELNF(s('Scan'));--$ ENDIF
  n:=ti;
  LOOP
    n:=n+r;
    ch_n:=stilling(stOff+ n);
    EXIT WHEN ch_n<>spc;
  END LOOP; 
  IF ch_n<>edge THEN
    IF UPPER_n(ch_n)=bQ THEN
      Black:= ch_n=bQ;
      IF Black THEN BlF(stDqueens) :=  BlF(stDqueens) + 1; ELSE WhF(stDqueens) := WhF(stDqueens) + 1; END IF;
      LOOP -- find piece behind queen
        n:=n+r;
        ch_n:=stilling(stOff+ n);
        EXIT WHEN ch_n<>spc;
      END LOOP; 
      IF UPPER_n(ch_n)=bQ THEN
        IF ch_n=bQ THEN BlF(stDqueens) :=  BlF(stDqueens) + 1;  ELSE WhF(stDqueens) := WhF(stDqueens) + 1; END IF;
      ELSIF NOT Diag AND ((UPPER_n(ch_n)=bR) OR (UPPER_n(ch_n)=bC)) THEN
        IF (ch_n=bR) OR (ch_n=bC) THEN 
          IF Black THEN BlF(stDrooksB) := BlF(stDrooksB) + 1; ELSE BlF(stDrooks) := BlF(stDrooks) + 1; END IF;
        ELSE
          IF NOT Black THEN WhF(stDrooksB) := WhF(stDrooksB) + 1; ELSE WhF(stDrooks) := WhF(stDrooks) + 1; END IF;
        END IF;
      ELSIF Diag AND (UPPER_n(ch_n)=bB) THEN
        IF ch_n=bB THEN
          IF Black THEN BlF(stDbishopsB) := BlF(stDbishopsB) + 1; ELSE WhF(stDbishops) := WhF(stDbishops) + 1; END IF;
        ELSE
          IF NOT Black THEN WhF(stDbishopsB) := WhF(stDbishopsB) +1; ELSE WhF(stDbishops) := WhF(stDbishops) + 1; END IF;
        END IF;
      END IF;
    ELSIF NOT Diag AND ((UPPER_n(ch_n)=bR) OR (UPPER_n(ch_n)=bC)) THEN
      IF (ch_n=bR) OR (ch_n=bC) THEN BlF(stDrooks) := BlF(stDrooks) + 1; ELSE WhF(stDrooks) := WhF(stDrooks) + 1; END IF;
      LOOP -- find piece behind rook
        n:=n+r;
        ch_n:=stilling(stOff+ n);
        EXIT WHEN ch_n<>spc;
      END LOOP; 
      IF UPPER_n(ch_n)=bQ THEN
        IF ch_n=bQ THEN BlF(stDqueens) := BlF(stDqueens) + 1; ELSE WhF(stDqueens) := WhF(stDqueens) + 1; END IF;
      ELSIF (UPPER_n(ch_n)=bR) OR (UPPER_n(ch_n)=bC) THEN
        IF (ch_n=bR) OR (ch_n=bC) THEN BlF(stDrooks) := BlF(stDrooks) + 1; ELSE WhF(stDrooks) := WhF(stDrooks) + 1; END IF;
      END IF;
    ELSIF Diag AND (UPPER_n(ch_n)=bB) THEN
      IF ch_n=bB THEN BlF(stDbishops) := BlF(stDbishops) + 1; ELSE WhF(stDbishops) := WhF(stDbishops) + 1; END IF;
      LOOP -- find piece behind bishop
        n:=n+r;
        ch_n:=stilling(stOff+ n);
        EXIT WHEN ch_n<>spc;
      END LOOP; 
      IF UPPER_n(ch_n)=bQ THEN
        IF ch_n=bQ THEN BlF(stDqueens) :=  BlF(stDqueens) + 1;  ELSE WhF(stDqueens) := WhF(stDqueens) + 1; END IF;
      ELSIF (UPPER_n(ch_n)=bB) THEN
        IF ch_n=bB THEN BlF(stDbishops) := BlF(stDbishops) + 1; ELSE WhF(stDbishops) := WhF(stDbishops) + 1; END IF;
      END IF;
    END IF;
  END IF;
END scan;
BEGIN  --Egain
  FOR n IN stDcount..stDking LOOP
    WhF(n):=0;
    BlF(n):=0;
  END LOOP;
  -- count pawns
  IF (stilling(stOff+ ti+ 9)=bP) OR (stilling(stOff+ ti+ 9)=bE) THEN BlF(stDpawns) := BlF(stDpawns) + 1; END IF;
  IF (stilling(stOff+ ti+11)=bP) OR (stilling(stOff+ ti+11)=bE) THEN BlF(stDpawns) := BlF(stDpawns) + 1; END IF;
  IF  stilling(stOff+ ti- 9)=wP THEN WhF(stDpawns) := WhF(stDpawns) + 1; END IF;
  IF  stilling(stOff+ ti-11)=wP THEN WhF(stDpawns) := WhF(stDpawns) + 1; END IF;
 
  -- count knights
  IF  UPPER_n(stilling(stOff+ ti+21))=bN THEN
    IF stilling(stOff+ ti+21)=bN THEN BlF(stDknights) := BlF(stDknights) + 1; ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
  IF  UPPER_n(stilling(stOff+ ti+19))=bN THEN
    IF stilling(stOff+ ti+19)=bN THEN BlF(stDknights) := BlF(stDknights) + 1;  ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
  IF  UPPER_n(stilling(stOff+ ti+12))=bN THEN
    IF stilling(stOff+ ti+12)=bN THEN BlF(stDknights) := BlF(stDknights) + 1; ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
  IF  UPPER_n(stilling(stOff+ ti+ 8))=bN THEN
    IF stilling(stOff+ ti+ 8)=bN THEN BlF(stDknights) := BlF(stDknights) + 1; ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
  IF  UPPER_n(stilling(stOff+ ti-12))=bN THEN
    IF stilling(stOff+ ti-12)=bN THEN BlF(stDknights) := BlF(stDknights) + 1; ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
  IF  UPPER_n(stilling(stOff+ ti- 8))=bN THEN
    IF stilling(stOff+ ti- 8)=bN THEN BlF(stDknights) := BlF(stDknights) + 1; ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
  IF  UPPER_n(stilling(stOff+ ti-21))=bN THEN
    IF stilling(stOff+ ti-21)=bN THEN BlF(stDknights) := BlF(stDknights) + 1; ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
  IF  UPPER_n(stilling(stOff+ ti-19))=bN THEN
    IF stilling(stOff+ ti-19)=bN THEN BlF(stDknights) := BlF(stDknights) + 1; ELSE WhF(stDknights) := WhF(stDknights) + 1; END IF;
  END IF;
 
  -- count kings
  IF    (UPPER_n(stilling(stOff+ ti+ 1))=bK) OR (UPPER_n(stilling(stOff+ ti+ 1))=bM) THEN
    IF stilling(stOff+ ti+ 1)=UPPER_n(stilling(stOff+ ti+ 1)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  ELSIF (UPPER_n(stilling(stOff+ ti- 1))=bK) OR (UPPER_n(stilling(stOff+ ti- 1))=bM) THEN
    IF stilling(stOff+ ti- 1)=UPPER_n(stilling(stOff+ ti- 1)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  ELSIF (UPPER_n(stilling(stOff+ ti+10))=bK) OR (UPPER_n(stilling(stOff+ ti+10))=bM) THEN
    IF stilling(stOff+ ti+10)=UPPER_n(stilling(stOff+ ti+10)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  ELSIF (UPPER_n(stilling(stOff+ ti+11))=bK) OR (UPPER_n(stilling(stOff+ ti+11))=bM) THEN
    IF stilling(stOff+ ti+11)=UPPER_n(stilling(stOff+ ti+11)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  ELSIF (UPPER_n(stilling(stOff+ ti+ 9))=bK) OR (UPPER_n(stilling(stOff+ ti+ 9))=bM) THEN
    IF stilling(stOff+ ti+ 9)=UPPER_n(stilling(stOff+ ti+ 9)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  ELSIF (UPPER_n(stilling(stOff+ ti- 9))=bK) OR (UPPER_n(stilling(stOff+ ti- 9))=bM) THEN
    IF stilling(stOff+ ti- 9)=UPPER_n(stilling(stOff+ ti- 9)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  ELSIF (UPPER_n(stilling(stOff+ ti-10))=bK) OR (UPPER_n(stilling(stOff+ ti-10))=bM) THEN
    IF stilling(stOff+ ti-10)=UPPER_n(stilling(stOff+ ti-10)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  ELSIF (UPPER_n(stilling(stOff+ ti-11))=bK) OR (UPPER_n(stilling(stOff+ ti-11))=bM) THEN
    IF stilling(stOff+ ti-11)=UPPER_n(stilling(stOff+ ti-11)) THEN BlF(stDking) := BlF(stDking) + 1; ELSE WhF(stDking) := WhF(stDking) + 1; END IF;
  END IF;
 
  -- count queens,rooks,bishops
  scan(  1,FALSE);
  scan( -1,FALSE);
  scan( 10,FALSE);
  scan(-10,FALSE);
  scan( 11,TRUE);
  scan(-11,TRUE);
  scan(  9,TRUE);
  scan( -9,TRUE);
 
  -- count White and Black total attacks
  FOR n IN stDpawns..stDking LOOP
    WhF(stDcount):=WhF(stDcount)+WhF(n);
    BlF(stDcount):=BlF(stDcount)+BlF(n);
  END LOOP;
  OwnCount:=WhF(stDcount);
 
  FirstCountAttacker:=0;
  IF (WhF(stDcount)>0) THEN
    risk:=ValueCalc(vcxOff+ bA) (vcyOff+ UPPER_n(stilling(stOff+ ti)));
    ValueC:=Fight(WhF,BlF,risk);
    IF BlF(stDcount)>0 THEN
      n:=stDpawns;
      WHILE BlF(n)=0 LOOP n := n  + 1; END LOOP;
      FirstCountAttacker:=n;
    END IF;
  END IF;

  RETURN(ValueC);  
END Egain;
 
--cf=20, Activity not used

FUNCTION QFind(p_stilling PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE,
               Activityy  SIMPLE_INTEGER,
               far        SIMPLE_INTEGER,
               farfar     SIMPLE_INTEGER,
               cf         SIMPLE_INTEGER,
               p_Qdepth   SIMPLE_INTEGER,
               p_Chess      BOOLEAN,
               p_farFra   SIMPLE_INTEGER,
               p_farTil   SIMPLE_INTEGER,
               farfarFra  SIMPLE_INTEGER,
               farfarTil  SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
  farFra   SIMPLE_INTEGER := p_farfra;
  farTil   SIMPLE_INTEGER := p_fartil;
  TYPE HAtype IS VARRAY(78) OF SIMPLE_INTEGER; -- pl/sql offset=-10
  haOff CONSTANT SIMPLE_INTEGER := -10;
  HA HAtype :=HAtype();  --ARRAY(11..88) of INTEGER
  dyb SIMPLE_INTEGER     := 0;
  fr SIMPLE_INTEGER      := 0;
  ti SIMPLE_INTEGER      := 0;
  retning SIMPLE_INTEGER := 0;
  cnt SIMPLE_INTEGER     := 0;
  countt SIMPLE_INTEGER  := 0;
  VluTmp SIMPLE_INTEGER  := 0;
  c1 SIMPLE_INTEGER      := 0;
  c2 SIMPLE_INTEGER      := 0;
  c3 SIMPLE_INTEGER      := 0;
  cntAtt SIMPLE_INTEGER  := 0;
  ha1st SIMPLE_INTEGER   := 0;
  ha2nd SIMPLE_INTEGER   := 0;
  cntAm SIMPLE_INTEGER   := 0;
  n SIMPLE_INTEGER       := 0;
  m SIMPLE_INTEGER       := 0;
  SkipValue SIMPLE_INTEGER := 0;
  MinEgain SIMPLE_INTEGER  := 0;
  KING SIMPLE_INTEGER      := 0;
  ChsCnt SIMPLE_INTEGER    := 0;
  FirstCountAttacker SIMPLE_INTEGER := 0;
  OwnCount SIMPLE_INTEGER  := 0;
  vc SIMPLE_INTEGER        := 0;
  tiC SIMPLE_INTEGER     := 0;
  vl SIMPLE_INTEGER      := 0;
  HAfr SIMPLE_INTEGER    := 0;
  repFra SIMPLE_INTEGER  := 0;
  repTil SIMPLE_INTEGER  := 0;
  Qdepth     SIMPLE_INTEGER := p_Qdepth;
  stilling PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE := p_stilling;
  frc SIMPLE_INTEGER  := 0;
  movetyp  MOVETYPE:=MOVEnormal ;
  Trk      TRAEKDATA := TRAEKDATA();
  TraekTst TRKDATA;
  fmax     TRKDATA;
  Still    PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE := PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE();
  Mirrt    BOOLEAN;
  MATE     BOOLEAN;
  CHESS    BOOLEAN;
  EatOnly  BOOLEAN;
  skipp    BOOLEAN;
  ChessYes BOOLEAN;
BEGIN
  HA.extend(78);
  Trk.extend(116);
  PL_PIG_CHESS_ENGINE_EVAL.Depth := PL_PIG_CHESS_ENGINE_EVAL.Depth + 1;
  Qdepth := Qdepth + 1;
  MATE:=TRUE;
  Mirrt:=stilling(stOff+ HvisTur)=bT;
  IF Mirrt THEN
    Mirror(stilling);
  END IF;
  IF (MOD(PL_PIG_CHESS_ENGINE_EVAL.Depth, 2)=1) = BlacksTurn THEN
    PL_PIG_CHESS_ENGINE_EVAL.pd:=PL_PIG_CHESS_ENGINE_EVAL.pdb;
  ELSE
    PL_PIG_CHESS_ENGINE_EVAL.pd:=PL_PIG_CHESS_ENGINE_EVAL.pdw;
  END IF;
  IF NOT p_Chess THEN
    FOR n IN 11..88 LOOP
      IF stilling(stOff+ n)>wA THEN
        HA(haOff+ n):=2; -- own piece, but still not proofed movable
      ELSE
        HA(haOff+ n):=0;
      END IF;
    END LOOP;
  END IF;
  IF PL_PIG_CHESS_ENGINE_EVAL.Depth>MaxStackDepth THEN
    QFindCnt :=QFindCnt +1;
    SkipValue:=PL_PIG_CHESS_ENGINE_EVAL.Eval(stilling,Activityy,FALSE,-9999,9999);
    PL_PIG_CHESS_ENGINE_EVAL.Depth := PL_PIG_CHESS_ENGINE_EVAL.Depth - 1;
    Qdepth := Qdepth - 1;
    RETURN(SkipValue);
  END IF;
  ChessYes := PL_PIG_CHESS_ENGINE_EVAL.Depth<MaxStackDepth-2;
  IF stilling(stOff+ 85)=bM THEN
    KING:=85;
  ELSE
    KING:=88;
    WHILE (stilling(stOff+ KING)<>bK) AND (KING>10) LOOP KING := KING - 1; END LOOP;
  END IF;
  fr:=10;
  ti:=89;
  retning:=0;
  MinEgain:=1;
  countt:=0;
  EatOnly:=FALSE;
  LOOP           -- lav liste med alle slag (countt) + skakker + QNpromotions
    GetNext(stilling,fr,ti,retning,movetyp);
    IF (fr<89) THEN
      MATE:=FALSE;
 
      frc:=stilling(stOff+ fr);
      HA(haOff+ fr):=1;
      IF (frc<>wK) AND (frc<>wM) THEN
        IF ChessYes OR (SET_IN(MOVEslag, movetyp)) THEN
          IF (frc=wB) OR (frc=wQ) THEN -- check for chess on diagonals
            IF (MOD(ti-KING,11)=0) OR ((ti-KING) MOD 9=0) THEN
              IF  MOD(ti-KING,11)=0 THEN
                IF ti>KING THEN
                  n:=ti-11;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n-11; END LOOP;
                ELSE
                  n:=ti+11;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n+11; END LOOP;
                END IF;
              ELSE
                IF ti>KING THEN
                  n:=ti-9;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n-9; END LOOP;
                ELSE
                  n:=ti+9;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n+9; END LOOP;
                END IF;
              END IF;
              IF n=KING THEN SET_INCL(movetyp,MOVEskak); END IF; -- else mark as bound piece
            END IF;                                     
          END IF;
          IF (frc=wR) OR (frc=wC) OR (frc=wQ) THEN -- check for chess on rows 
            IF FLOOR(ti/10)=FLOOR(KING/10) OR MOD(ti,10)=MOD(KING,10) THEN
              IF FLOOR(ti/10)=FLOOR(KING/10) THEN
                IF ti>KING THEN
                  n:=ti-1;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n-1; END LOOP;
                ELSE
                  n:=ti+1;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n+1; END LOOP;
                END IF;
              ELSE
                IF ti>KING THEN
                  n:=ti-10;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n-10; END LOOP;
                ELSE
                  n:=ti+10;
                  WHILE stilling(stOff+ n)=spc LOOP n:=n+10; END LOOP;
                END IF;
              END IF;
              IF n=KING THEN SET_INCL(movetyp,MOVEskak); END IF; -- else mark as bound piece
            END IF;
          END IF;
          IF (frc=wN) AND ((ti-KING=12) OR (ti-KING=-12) OR
                          (ti-KING=21) OR (ti-KING=-21) OR
                          (ti-KING= 8) OR (ti-KING= -8) OR
                          (ti-KING=19) OR (ti-KING=-19)) THEN
            SET_INCL(movetyp,MOVEskak);
            -- and check for attack on Q and R (family chess)
          END IF;
        END IF;     
        IF (frc=wP) THEN
          IF fr>70 THEN -- promote 
            frc:=spc;
            IF ti>80 THEN  -- promote to queen
              frc:=wQ;
            ELSIF (ti>50) AND (ti<59) THEN -- promote to knight if chess
              tiC:=ti+30;
              IF (tiC-KING=12) OR (tiC-KING=21) OR (tiC-KING= 8) OR (tiC-KING=19) THEN
                SET_INCL(movetyp,MOVEskak);
                frc:=wN;
              END IF;
            END IF;
          ELSIF (ti+9=KING) OR (ti+11=KING) THEN
            SET_INCL(movetyp,MOVEskak);
          END IF;
        END IF;
      END IF;
      IF (SET_IN(MOVEslag , movetyp))
      OR ChessYes AND (SET_IN (MOVEskak ,movetyp)) AND (Qdepth<=SkakDepth)
      OR (fr>70) AND (stilling(stOff+ fr)=wP) AND ((ti>80) OR (ti>50) AND (ti<59))
      OR p_Chess THEN
        IF SET_IN (MOVEslag,movetyp) THEN
          IF (stilling(stOff+ ti)=spc) AND (fr<59) AND (frc=wP) THEN -- en-passant
            n:=0;
          ELSE
            n:=ValueCalc(vcxOff+ UPPER_n(stilling(stOff+ fr))) (vcyOff+ UPPER_n(stilling(stOff+ ti)));
          END IF;
          IF (n=0) AND (Qdepth<=XchDepth) THEN n:=MinEgain; END IF;
          IF n<MinEgain THEN
            m:=Egain(stilling,fr,ti,OwnCount,FirstCountAttacker);
            IF m>0 THEN
              IF (n>-190) OR (FirstCountAttacker=0) THEN -- TAB: 470-300=170,300-100=200
                n:=m;
              ELSE
                CASE   -- !!!!!!!! FirstCountAttacker var 25518 CASE INDEX!!!*)
                WHEN FirstCountAttacker = stDpawns                  THEN vl:=PL_PIG_CHESS_ENGINE_EVAL.ValueB;
                WHEN FirstCountAttacker IN (stDknights,stDbishopsB) THEN vl:=PL_PIG_CHESS_ENGINE_EVAL.Value_S;
                WHEN FirstCountAttacker IN (stDrooks,stDrooksB)     THEN vl:=PL_PIG_CHESS_ENGINE_EVAL.ValueT;
                WHEN FirstCountAttacker = stDqueens                 THEN vl:=PL_PIG_CHESS_ENGINE_EVAL.ValueD;
                WHEN FirstCountAttacker = stDking                   THEN vl:=PL_PIG_CHESS_ENGINE_EVAL.ValueK;
                ELSE
                  vl:=0;
                END CASE;
                IF n+vl>-100 THEN n:=m; END IF; --!!!!!!!!!!!*)
              END IF;
            ELSIF (SET_IN (MOVEskak , movetyp)) AND (Qdepth<2) THEN -- 1: se på ofre med skak
              n:=1;
            END IF;
          END IF;
 
          IF p_Chess AND (n>0) THEN
            EatOnly:=TRUE;
          END IF;
          IF n>=MinEgain THEN n:=n+20; END IF; -- Keeps'em better than just chess
        ELSIF ChessYes AND (SET_IN (MOVEskak,movetyp)) AND (Qdepth<=SkakDepth) THEN -- but not slag
          m:=Egain(stilling,fr,ti,OwnCount,FirstCountAttacker); -- needs FirstCountAttacker ONLY!!! 
          IF FirstCountAttacker=0 THEN
            n:=3;
          ELSE
            n:=-ValueCalc(vcxOff+ bA) (vcyOff+ UPPER_n(stilling(stOff+ fr)));
            CASE  -- 3-98 minus one
            WHEN FirstCountAttacker= stDpawns                   THEN n:=n+PL_PIG_CHESS_ENGINE_EVAL.ValueB-1;
            WHEN FirstCountAttacker IN( stDknights,stDbishopsB) THEN n:=n+PL_PIG_CHESS_ENGINE_EVAL.Value_S-1;
            WHEN FirstCountAttacker IN( stDrooks,stDrooksB)     THEN n:=n+PL_PIG_CHESS_ENGINE_EVAL.ValueT-1;
            WHEN FirstCountAttacker= stDqueens                  THEN n:=n+PL_PIG_CHESS_ENGINE_EVAL.ValueD-1;
            WHEN FirstCountAttacker= stDking                    THEN n:=900;
            END CASE;
            IF n>0 THEN n:=2+FLOOR(n/64); END IF;
          END IF;
        ELSIF p_Chess THEN
          n:=-1; -- ! must be negative..mark as a move after a check
        ELSE -- promotion, (fr>70) AND (stilling(stOff+ fr)=wP) AND ((ti>80) OR (ti>50) AND (ti<59))
          n:=800;
        END IF;
        IF (n>=MinEgain) OR p_Chess AND (NOT EatOnly OR (ChessYes AND (SET_IN (MOVEslag,movetyp)))) THEN -- worth to try, store move
          countt := countt  + 1;
--WRT('1685 '||countt);
          Trk(countt).Vlu:=      n;
          Trk(countt).Fra:=     fr;
          Trk(countt).Til:=     ti;
          Trk(countt).Typ:=movetyp;
          IF NOT p_Chess AND (ValueCalc(vcxOff+ UPPER_n(stilling(stOff+ fr))) (vcyOff+ UPPER_n(stilling(stOff+ ti)))>0) THEN
--$ IF Test0  WRITELNF(s('ATT=3: ')+l(fr));--$ ENDIF
            HA(haOff+ fr):=3; -- mark as already found a gaining move
          END IF;
        END IF;
      ELSE
        NULL;
      END IF;
    END IF;
    EXIT WHEN fr>88;
  END LOOP; 
  cntAtt:=countt;
  ha1st:=0;
  ha2nd:=0;

  IF NOT p_Chess THEN
    FOR fr IN 11..88 LOOP -- is piece attacked?
      IF HA(haOff+ fr)>0 THEN
        HAfr:=0;
        frc:=stilling(stOff+ fr); -- skip if k,m,p ???!!!*)
        IF (stilling(stOff+ fr+11)=bP) OR (stilling(stOff+ fr+11)=bE)
          OR (stilling(stOff+ fr+ 9)=bP) OR (stilling(stOff+ fr+ 9)=bE) THEN
          CASE 
           WHEN frc in( wN,wB)     THEN  HAfr:=200;
           WHEN frc in( wR,wC,wQ) THEN HAfr:=370;
          ELSE NULL; END CASE;
        ELSIF (frc=wQ) OR (frc=wR) OR (frc=wC) THEN
          IF (stilling(stOff+ fr+12)=bN) OR (stilling(stOff+ fr-12)=bN)
          OR    (stilling(stOff+ fr+21)=bN) OR (stilling(stOff+ fr-21)=bN)
          OR    (stilling(stOff+ fr+ 8)=bN) OR (stilling(stOff+ fr- 8)=bN)
          OR    (stilling(stOff+ fr+19)=bN) OR (stilling(stOff+ fr-19)=bN) THEN
            CASE
              WHEN frc= wQ     THEN HAfr:=350;
              WHEN frc in (wR,wC) THEN HAfr:=170;
              ELSE NULL; 
            END CASE;
          ELSIF (stilling(stOff+ fr+11)=bB) OR
                (stilling(stOff+ fr+ 9)=bB) OR
                (stilling(stOff+ fr-11)=bB) OR
                (stilling(stOff+ fr- 9)=bB) OR
                (stilling(stOff+ fr+11)=spc) AND (stilling(stOff+ fr+22)=bB)  OR 
                (stilling(stOff+ fr-11)=spc) AND (stilling(stOff+ fr-22)=bB)  OR 
                (stilling(stOff+ fr+ 9)=spc) AND (stilling(stOff+ fr+18)=bB)  OR 
                (stilling(stOff+ fr- 9)=spc) AND (stilling(stOff+ fr-18)=bB)  OR
                (stilling(stOff+ fr+11)=spc) AND (stilling(stOff+ fr+22)=spc) AND (stilling(stOff+ fr+33)=bB)  OR 
                (stilling(stOff+ fr-11)=spc) AND (stilling(stOff+ fr-22)=spc) AND (stilling(stOff+ fr-33)=bB)  OR 
                (stilling(stOff+ fr+ 9)=spc) AND (stilling(stOff+ fr+18)=spc) AND (stilling(stOff+ fr+27)=bB)  OR 
                (stilling(stOff+ fr- 9)=spc) AND (stilling(stOff+ fr-18)=spc) AND (stilling(stOff+ fr-27)=bB)  THEN --uncomplete!*)
            CASE
              WHEN frc=wQ     THEN HAfr:=350;
              WHEN frc IN (wR,wC) THEN HAfr:=170;
              ELSE NULL;
            END CASE;
          ELSIF (frc=wQ) AND (
            (stilling(stOff+ fr+10)=bR) OR
            (stilling(stOff+ fr-10)=bR) OR
            (stilling(stOff+ fr+ 1)=bR) OR
            (stilling(stOff+ fr- 1)=bR) OR
            (stilling(stOff+ fr+10)=spc) AND (stilling(stOff+ fr+20)=bR)  OR 
            (stilling(stOff+ fr-10)=spc) AND (stilling(stOff+ fr-20)=bR)  OR 
            (stilling(stOff+ fr+ 1)=spc) AND (stilling(stOff+ fr+ 2)=bR)  OR 
            (stilling(stOff+ fr- 1)=spc) AND (stilling(stOff+ fr- 2)=bR)  OR
            (stilling(stOff+ fr+10)=spc) AND (stilling(stOff+ fr+20)=spc) AND (stilling(stOff+ fr+30)=bR)  OR 
            (stilling(stOff+ fr-10)=spc) AND (stilling(stOff+ fr-20)=spc) AND (stilling(stOff+ fr-30)=bR)  OR 
            (stilling(stOff+ fr+ 1)=spc) AND (stilling(stOff+ fr+ 2)=spc) AND (stilling(stOff+ fr+ 3)=bR)  OR 
            (stilling(stOff+ fr- 1)=spc) AND (stilling(stOff+ fr- 2)=spc) AND (stilling(stOff+ fr- 3)=bR)) THEN
            HAfr:=180;
          END IF;
        END IF;
        IF HAfr>0 THEN -- attacked, store move(s)
          IF HAfr>ha2nd THEN
            IF HAfr>ha1st THEN
              ha2nd:=ha1st;
              ha1st:=HAfr;
            ELSE
              ha2nd:=HAfr;
            END IF;
          END IF;
          n:=fr-1;
          ti:=89;
          retning:=0;
          cntAm:=0; -- count of moves for attacked piece
          LOOP  -- maybe only on HA(haOff+ fr)=1 ???
            GetNext(stilling,n,ti,retning,movetyp);
            IF (n=fr) THEN
              -- what about checks to set chess flag ?
              cntAm := cntAm + 1;
              cntAtt := cntAtt + 1;
              Trk(cntAtt).Vlu:=   HAfr;
              Trk(cntAtt).Fra:=     fr;
              Trk(cntAtt).Til:=     ti;
              Trk(cntAtt).Typ:=movetyp;
            END IF;
            EXIT WHEN n>fr;
          END LOOP; 
          IF cntAm=0 THEN -- bound or lost piece
            IF ha2nd<HAfr THEN
              ha2nd:=HAfr;
            END IF;
          ELSIF cntAm<3 THEN -- only one move possible
            vc:=ValueCalc(vcxOff+ UPPER_n(stilling(stOff+ fr))) (vcyOff+ UPPER_n(stilling(stOff+ Trk(cntAtt).Til)));
            IF vc<=-HAfr THEN
                IF (cntAm=1) OR (stilling(stOff+ fr)=wQ) THEN
                    IF ha2nd<HAfr THEN
                       ha2nd:=HAfr;
                    END IF;
                END IF;
            END IF;
          END IF;
        END IF;
      END IF;--IF HA(haOff+ fr)>0
        -- HA(haOff+ fr):=HAfr; p.t. not used later 
    END LOOP;--FOR fr IN 11..88
  END IF; --IF not chess


  IF MATE THEN -- no moves possible 
    IF p_Chess THEN
      fmax.Typ:=MOVEmat;
      fmax.Vlu:=-16383;
    ELSE
      fmax.Typ:=MOVEpat;
      fmax.Vlu:=0;
    END IF;
  ELSE
    QFindCnt :=QFindCnt +1;
    SkipValue:=PL_PIG_CHESS_ENGINE_EVAL.Eval(stilling,Activityy,FALSE,fmax.Vlu,far)-FLOOR((ha2nd-ha1st)/32);
    IF p_Chess THEN
      fmax.Vlu:=-20000;
    ELSE
      fmax.Vlu:=SkipValue;
    END IF;
    IF (countt>1) AND (fmax.Vlu<far) THEN
      QSortTrk(Trk,1,countt);
      --SHellSort(Trk,countt);
      IF Trk(1).Vlu>31 THEN SkipValue:=SkipValue+FLOOR(Trk(1).Vlu/32); END IF;
      IF NOT p_Chess THEN fmax.Vlu:=SkipValue; END IF;
    END IF;

    IF Qdepth=1 THEN
      IF Mirrt THEN
        StartEval:=-SkipValue;
      ELSE
        StartEval:=SkipValue;
      END IF;
    END IF;
 
    IF (countt>0) AND (fmax.Vlu<far) THEN 
      fmax.Fra:=10;
      fmax.Til:=89;
      cnt:=0;
      LOOP                            -- for cnt:=1..countt
        cnt := cnt + 1;  
        IF NOT EatOnly OR (Trk(cnt).Vlu>0) THEN
          skipp:=FALSE;
          IF NOT p_Chess THEN
 
            -- 3: if not a chess and fmax gain is bigger than the piece to
            --      eat + an max positional value gain (MaxPosValGain about 50)
            IF NOT (SET_IN(MOVEskak,Trk(cnt).Typ))
            --AND (fmax.Vlu-SkipValue>ValueCalc(bA,UPPER_n(stilling(stOff+ Trk(cnt).Til)))+MaxPosValGain) THEN

            AND (fmax.Vlu-SkipValue>ValueCalc(vcxOff+ bA) (vcyOff+ UPPER_n(stilling(stOff+ Trk(cnt).Til)))+MaxPosValGain) THEN
              skipp:=TRUE; -- !!!!!! under-promotion,ep fails? !!!!!!!*)
            END IF;
          ELSE
            IF countt>2 THEN
              frc:=UPPER_n(stilling(stOff+ Trk(cnt).Fra));
              IF (frc<>bK) AND (frc<>bM) AND NOT (SET_IN(MOVEslag,Trk(cnt).Typ)) THEN
                m:=Egain(stilling,Trk(cnt).Fra,Trk(cnt).Til,OwnCount,FirstCountAttacker);
--$ IF Test  IF Tag() AND (OwnCount<2) THEN WRITELNF(s('SKIP<2 =')+l(OwnCount)); END IF;--$ ENDIF
                IF OwnCount<2 THEN skipp:=TRUE; END IF;
              END IF;
            END IF; 
          END IF;
 
          -- 4: skip if best position and move is piece back again
          IF ((SkipValue>0) OR (fmax.Vlu>0))
            AND (Trk(cnt).Fra=farfarTil)
            AND (Trk(cnt).Til=farfarFra) THEN
            --skipp:=TRUE;
            NULL;
          END IF;
 
          IF NOT skipp THEN
            Still:=stilling;
            CHESS:=SET_IN(MOVEskak,Trk(cnt).Typ);
            IF (SET_IN(MOVEslag,Trk(cnt).Typ))
            OR (Trk(cnt).Fra>70) AND (stilling(stOff+ Trk(cnt).Fra)=wP) THEN
              repFra:=0;
              repTil:=0;
              farFra:=0;
              farTil:=0;
            ELSE 
              repFra:=Trk(cnt).Fra;
              repTil:=Trk(cnt).Til;
            END IF;
            DoMove(Still, Trk(cnt).Fra, Trk(cnt).Til, Trk(cnt).Typ);
            Trk(cnt).Vlu:=-QFind(Still,Activityy,-fmax.Vlu,-far,cf,Qdepth,
                                 CHESS,repFra,repTil,farFra,farTil);
            IF NOT Push AND (Qdepth<10) THEN 
              NULL; --AEM();--active-event-monitor??? 
            END IF;
            IF Trk(cnt).Vlu>fmax.Vlu THEN 
              fmax:=Trk(cnt);
            END IF;
          END IF;
        ELSE
          NULL;
        END IF;
        EXIT WHEN (fmax.Vlu>far) OR (cnt=countt) OR Push;
      END LOOP; 
      -- OR (fmax.Vlu>1200)
      --   OR NOT Mirrt AND (fmax.Vlu>StartEval+1000)
      --   OR Mirrt AND (fmax.Vlu>1000-StartEval) ;
 
      IF NOT p_Chess AND ((fmax.Vlu<SkipValue) OR (fmax.Fra=10)) THEN
        fmax.Vlu:=SkipValue;
      END IF;
    ELSE -- IF countt=0: -- slut
      fmax.Vlu:=SkipValue;
    END IF;
  END IF;

--$ IF Test IF Tag() THEN ShowLine('EvQf=',fmax.Vlu,FALSE); WRITELNF(0); END IF;--$ ENDIF
  PL_PIG_CHESS_ENGINE_EVAL.Depth := PL_PIG_CHESS_ENGINE_EVAL.Depth - 1;
  Qdepth := Qdepth - 1;

  IF fmax.Vlu>16000 THEN fmax.Vlu := fmax.Vlu - 1; END IF;
  RETURN(fmax.Vlu);
END QFind;

 
PROCEDURE ClearHistory(p_cnt SIMPLE_INTEGER, p_black BOOLEAN) IS
  n SIMPLE_INTEGER:=0;
  cnt SIMPLE_INTEGER := p_cnt;
  black  SIMPLE_INTEGER:=CASE WHEN p_black then 2 ELSE 1 END;
BEGIN
  IF cnt>0 THEN
    IF cnt>HisMax THEN cnt:=HisMax; END IF;
    FOR n IN 1..HisMax-cnt LOOP
      Repete(black) (n) :=Repete(black) (n+cnt);
    END LOOP;
    FOR n IN 1+HisMax-cnt..HisMax LOOP
      Repete(black) (n).tr.Fra:=0;
      Repete(black) (n).tr.Til:=0;
    END LOOP;
  END IF;
END ClearHistory;
 
 
PROCEDURE AddHistory(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, 
                     fra SIMPLE_INTEGER,
                     til SIMPLE_INTEGER,
                     vlu SIMPLE_INTEGER)IS
-- NOTE: black positions are stored mirror'ed
  black SIMPLE_INTEGER:=1; --1=FALSE, 2=TRUE 
  n SIMPLE_INTEGER:=0;
  nn SIMPLE_INTEGER:=0;
  st PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE;
BEGIN
  IF (UPPER_n(stilling(stOff+ fra))=bP) OR (stilling(stOff+ til)<>spc) THEN
    ClearHistory(999,FALSE);
    ClearHistory(999,TRUE);
  ELSE
    black:=CASE WHEN stilling(stOff+ HvisTur)=bT THEN 2 ELSE 1 END;
    FOR nn IN 2..HisMax LOOP
      n :=HisMax-nn+2; --HisMax..2 BY -1
      Repete(black) (n) := Repete(black) (n-1);
    END LOOP;
    --WITH Repete(black,1) 
      st:=stilling;
      IF black=2 THEN
        Mirror(st);
        --fra:=MOD(fra,10)+10*(9-FLOOR(fra/10));
        --til:=MOD(til,10)+10*(9-FLOOR(til/10));
      END IF;
      repete(black) (1).tr.Fra:=fra;
      repete(black) (1).tr.Til:=til;
      repete(black) (1).tr.Vlu:=vlu;
    --END IF;
  END IF;
END AddHistory;
 


FUNCTION Equal_old(p_stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, p_still2 in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE) RETURN BOOLEAN IS
  --uses out to make the compare by reference (quicker) but no change of data.
BEGIN
  FOR n in 1..121 LOOP
     if p_stilling(stOff+ n) <> p_still2(n) THEN
       RETURN FALSE;
     end if;
  END LOOP;
  RETURN TRUE;
END Equal_old;



FUNCTION Equal(p_stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, p_still2 in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE) RETURN BOOLEAN IS
  --uses out to make the compare by reference (quicker) but no change of data.
  --First checks on 'coinflip' fields, makes compare 25% faster.
BEGIN--/* in PL/SQL is offset 11, logical: -10..110: A1-H8 = 11-88, HvidSort=wT | bN CAP=BLACK */
  IF p_stilling(121) <> p_still2(121) THEN -- 11+ hvistur (110) color is 50% for diff found
    RETURN FALSE;
  END IF;
  IF p_stilling(35) <> p_still2(35) THEN -- 11+ d2 for diff found
    RETURN FALSE;
  END IF;
  IF p_stilling(36) <> p_still2(36) THEN -- 11+ e2 for diff found
    RETURN FALSE;
  END IF;
  IF p_stilling(85) <> p_still2(85) THEN -- 11+ d7 for diff found
    RETURN FALSE;
  END IF;
  IF p_stilling(86) <> p_still2(86) THEN -- 11+ e7 for diff found
    RETURN FALSE;
  END IF;
  FOR n in 22..29 LOOP -- 11+ 11..18 (first row)
     if p_stilling(n) <> p_still2(n) THEN
       RETURN FALSE;
     end if;
  END LOOP;
  FOR n in 92..99 LOOP -- 11+ 81..88 (last row)
     if p_stilling(n) <> p_still2(n) THEN
       RETURN FALSE;
     end if;
  END LOOP;
  FOR n in 32..89 LOOP -- 11+ 21..78
     if p_stilling(n) <> p_still2(n) THEN
       RETURN FALSE;
     end if;
  END LOOP;
  --WRT('EQUAL');
  RETURN TRUE;
END Equal;



PROCEDURE Find(p_stilling PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, 
               p_dybde     SIMPLE_INTEGER, 
               far         SIMPLE_INTEGER,
               farfar      SIMPLE_INTEGER,
               cf          SIMPLE_INTEGER, --cf=20*)  
               traek in out TRKDATA, 
               p_farFra    SIMPLE_INTEGER,
               p_farTil    SIMPLE_INTEGER,
               farfarFra   SIMPLE_INTEGER,
               farfarTil   SIMPLE_INTEGER) IS
  dybde     SIMPLE_INTEGER := p_dybde; 
  farFra    SIMPLE_INTEGER := p_farFra;
  farTil    SIMPLE_INTEGER := p_farTil;
  dyb     SIMPLE_INTEGER:=0;
  fr      SIMPLE_INTEGER:=0;
  ti      SIMPLE_INTEGER:=0;
  retning SIMPLE_INTEGER:=0;
  cnt     SIMPLE_INTEGER:=0;
  countt  SIMPLE_INTEGER:=0;
  VluTmp  SIMPLE_INTEGER:=0;
  c1      SIMPLE_INTEGER:=0;
  c2      SIMPLE_INTEGER:=0;
  c3      SIMPLE_INTEGER:=0;
  n       SIMPLE_INTEGER:=0;
  nn      SIMPLE_INTEGER:=0;
  KING    SIMPLE_INTEGER:=0;
  reps    SIMPLE_INTEGER:=0;
  til     SIMPLE_INTEGER:=0;
  repFra  SIMPLE_INTEGER:=0;
  repTil  SIMPLE_INTEGER:=0;
  movetyp  MOVETYPE:=0;
  Trk      TRAEKDATA := TRAEKDATA();
  TraekTst TRKDATA;
  fmax     TRKDATA;
  repmove  TRKDATA;
  stilling PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE:= p_stilling;
  Still    PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE:=PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE();
  Mirrt      SIMPLE_INTEGER:=1;  --BOOLEAN; nu 1=FALSE 2=TRUE
  repper      BOOLEAN;
  rep1        BOOLEAN;
  Chess       BOOLEAN; 
  FirstCalled BOOLEAN;
BEGIN
  FindCnt :=FindCnt +1;
  Trk.extend(116);
  PL_PIG_CHESS_ENGINE_EVAL.Depth := PL_PIG_CHESS_ENGINE_EVAL.Depth + 1;
  FirstCalled := FirstCall; -- tells it's called from FindTrk 
  FirstCall   := FALSE;
  IF stilling(stOff+ HvisTur)=bT THEN 
    Mirrt := 2;
    Mirror(stilling);
  END IF;
  Chess:=FALSE;
  IF (MOD(PL_PIG_CHESS_ENGINE_EVAL.Depth, 2)=1) = BlacksTurn THEN
    PL_PIG_CHESS_ENGINE_EVAL.pd:=PL_PIG_CHESS_ENGINE_EVAL.pdb;
  ELSE
    PL_PIG_CHESS_ENGINE_EVAL.pd:=PL_PIG_CHESS_ENGINE_EVAL.pdw;
  END IF;
  IF stilling(stOff+ 85)=bM THEN
    KING:=85;
  ELSE
    KING:=11;
    WHILE (stilling(stOff+ KING)<>bK) AND (KING<89) LOOP KING := KING + 1; END LOOP;
  END IF;
--WRITELN(s('KING=')+l(KING));*)
  fr:=10;
  ti:=89;
  retning:=0;
  countt:=0;
  reps:=0;
  LOOP           -- lav liste med alle træk (count)
    GetNext(stilling,fr,ti,retning,movetyp);
    IF (fr<89) THEN
      countt := countt + 1;
      IF SET_IN (MOVEslag ,movetyp) THEN
        IF (stilling(stOff+ fr)=wP) AND (fr>70) THEN
          til:=ti;
          IF til<fr+9 THEN
            VluTmp:=-50;  -- Rook-promotion, so give low priority
            til:=til+20;
            IF til<fr+9 THEN
              IF til+2>fr THEN
                VluTmp:=200;  -- knight
                til:=til+10;
              ELSE
                VluTmp:=-90;  -- Bishop
                til:=til+20;
              END IF;
            END IF;
          ELSE  
            VluTmp:=880-100;  -- Queen
          END IF;
          VluTmp:=VluTmp+ValueCalc(vcxOff+ UPPER_n(stilling(stOff+ fr))) (vcyOff+ UPPER_n(stilling(stOff+ til)));
        ELSE
          IF stilling(stOff+ ti)=spc THEN
            VluTmp:=1;
          ELSE
            VluTmp:=ValueCalc(vcxOff+ UPPER_n(stilling(stOff+ fr))) (vcyOff+ UPPER_n(stilling(stOff+ ti)));
          END IF;
        END IF;
      ELSE
        IF (stilling(stOff+ fr)=wP) AND (fr>70) THEN
          til:=ti;
          IF til<fr+9 THEN
            VluTmp:=-50;  -- Rook-promotion, so give low priority 
            til:=til+20;
            IF til<fr+9 THEN
              IF til+2>fr THEN
                VluTmp:=200;  -- knight 
                til:=til+10;
              ELSE
                VluTmp:=-90;  -- Bishop 
                til:=til+20;
              END IF;
            END IF;
          ELSE  
            VluTmp:=880-100; -- Queen 
          END IF;
        ELSE
          --!!!!!!!!!!!!!!!!!! skal være der!!!
          --NULL;
          VluTmp := PL_PIG_CHESS_ENGINE_EVAL.pd(pdN(stilling(stOff+ fr),ti)) - PL_PIG_CHESS_ENGINE_EVAL.pd(pdN(stilling(stOff+ fr),fr)); 
        END IF;
      END IF;
      Trk(countt).Vlu:=VluTmp;
      Trk(countt).Fra:=fr;
      Trk(countt).Til:=ti;
      Trk(countt).Typ:=movetyp;
      IF PL_PIG_CHESS_ENGINE_EVAL.Depth=1 THEN
        n:=2;
        til:=Repete(Mirrt) (n).tr.Til;
        WHILE (n<=HisMax) AND (til<>0) AND (til<>90) LOOP 
          IF (ti=Repete(Mirrt) (n).tr.Til) THEN
            IF (fr=Repete(Mirrt) (n).tr.Fra) THEN
              IF Equal(stilling, Repete(Mirrt) (n).st) THEN
                --$ IF Test0WRITELN(s('!x7!:')+l(n));--$ ENDIF
                reps := reps + 1;
                repmove:=Trk(countt);
              END IF;
            END IF;
          END IF;
          n:=n+1;
          IF n<=HisMax THEN
            til:=Repete(Mirrt) (n).tr.Til;
          END IF;
        END LOOP;
      END IF;
    END IF;
    EXIT WHEN fr=89;
  END LOOP; 
  IF countt>1 THEN 
    QSortTrk(Trk,1,countt); 
  END IF; -- new! pre-sort to get better cut-offs
 
  dyb:=1;
  IF countt>0 THEN 
    IF (PL_PIG_CHESS_ENGINE_EVAL.Depth=1) AND (countt=1) THEN -- first move is only move!
      fmax:=Trk(1);
    ELSE
      --farfar := -20000;*)
      LOOP                              -- for dyb:=1..dybde
        IF (dyb=1) AND FALSE THEN
          fmax.Vlu:=farfar;
        ELSE
          fmax.Vlu:=-20000;
        END IF;
        cnt:=0;
        LOOP                            -- for cnt:=1..countt
          cnt := cnt + 1;
          IF (dyb=1) OR (Trk(cnt).Vlu>-12000) THEN -- hvis ikke sat mat
            Still:=stilling;
            DoMove(Still, Trk(cnt).Fra, Trk(cnt).Til, Trk(cnt).Typ);
  
            repper:=(reps>0) AND (repmove.Til=Trk(cnt).Til) AND (repmove.Fra=Trk(cnt).Fra);
            IF repper THEN
--$ IF Test0  WRITELNF(s('!Find: reps=')+l(reps)+s('!'));--$ ENDIF
              IF reps>1 THEN      -- 3'rd time
                Trk(cnt).Vlu:=DrawAccept;                    -- -50 .. 50 
                rep1:=FALSE;
              ELSE
                rep1:=TRUE;
              END IF;
            END IF;
            IF NOT repper OR rep1 THEN
              IF (SET_IN (MOVEslag ,Trk(cnt).Typ))
              OR (Trk(cnt).Fra>70) AND (stilling(stOff+ Trk(cnt).Fra)=wP) THEN
                repFra:=0;
                repTil:=0;
                farFra:=0;
                farTil:=0;
              ELSE
                repFra:=Trk(cnt).Fra;
                repTil:=Trk(cnt).Til;
              END IF;
              IF dyb=1 THEN
                Chess:=CheckSkak(Still,KING,FALSE);
                IF Chess AND (dybde=1) THEN -- expand when last move is a chess
                  Find(Still,1,-fmax.Vlu,-far,cf,TraekTst,repFra,repTil,farFra,farTil);
                  IF NOT STOPP THEN Trk(cnt).Vlu:=-TraekTst.Vlu; END IF;
                ELSE
                  Trk(cnt).Vlu:=-QFind(Still,countt,-fmax.Vlu,-far,cf,0,Chess,repFra,repTil,farFra,farTil);
                END IF;
              ELSE
                Find(Still,dyb-1,-fmax.Vlu,-far,cf,TraekTst,repFra,repTil,farFra,farTil);
                IF NOT STOPP THEN Trk(cnt).Vlu:=-TraekTst.Vlu; END IF;
                IF NOT Push THEN 
                  NULL; --AEM(); --!!!!!!!!!!!!!!!!!!!!!
                END IF;
              END IF;
              IF repper THEN -- adjust eval down 'cause opponent can take repetition
                IF Trk(cnt).Vlu>DrawAccept THEN Trk(cnt).Vlu:=DrawAccept; END IF;
              END IF;
            END IF;
            IF STOPP THEN
              IF (fmax.Vlu=farfar) OR (fmax.Vlu=-20000) THEN
                fmax:=Trk(1);
--$ IF Stamp W.CONCAT(W.s('=farfar ')+W.l(fmax.Fra)+W.c(12C)); --$ ENDIF
               END IF;
            ELSE
              IF Trk(cnt).Vlu>fmax.Vlu THEN
                fmax:=Trk(cnt);
              END IF;
            END IF;
          END IF;
          EXIT WHEN (cnt>=countt) -- normal END for cnt=1..count
           OR (fmax.Vlu>far) -- pruning cut
           OR (PL_PIG_CHESS_ENGINE_EVAL.Evals>MaxEvals) AND (dyb>1) -- Time cut
           OR (fmax.Vlu>16382) -- mate in one found, stop
           OR Push;            -- break, stop
        END LOOP; 
 
        -- !!!! if more than 3000 nodes on depth 1 then lower total depth>1 by 1
        -- set between 1000 and 20000 (def: 3000)
 
        IF (PL_PIG_CHESS_ENGINE_EVAL.Evals>MaxEvals) AND (dyb>1) THEN
          IF dyb<dybde THEN
            dybde:=dyb;
          END IF;
          STOPP:=TRUE;

        END IF;
        IF FirstCalled THEN
          IF dyb<=1 THEN 
            --$ IF Test WRITELNF(s('FirstCalled, dybde=')+l(dybde));--$ ENDIF
            IF (PL_PIG_CHESS_ENGINE_EVAL.Evals>2000) AND (dyb<dybde) THEN
              dybde := dybde - 1;
              --$ IF Test WRITELNF(s('AAA evals=')+l(SkakBrainEval.Evals)+s(', dec(dybde)'));--$ ENDIF
            END IF;
            IF NOT Chess AND (PL_PIG_CHESS_ENGINE_EVAL.Evals<30) THEN
              dybde := dybde + 1;
              --$ IF Test WRITELNF(s('BBB evals=')+l(SkakBrainEval.Evals)+s(', inc(dybde)'));--$ ENDIF
            END IF;
          END IF;
        END IF;
        IF (fmax.Vlu>12000) THEN dyb:=dybde; END IF; -- mate found, stop
        IF dyb<dybde THEN 
          QSortTrk(Trk,1,cnt);
          --ShellSort(Trk,cnt);
        END IF;
        dyb := dyb + 1;
        EXIT WHEN dyb>dybde;
      END LOOP; 
    END IF;
    IF PL_PIG_CHESS_ENGINE_EVAL.Depth=1 THEN
 
-- AddHistory called by SkakFil.GetStilling
      FOR nn IN HisMax..2 LOOP--BY -1 DO
        n :=HisMax-nn+2; --HisMax..2 BY -1
        Repete(Mirrt) (n):=Repete(Mirrt) (n-1);
      END LOOP;
      Repete(Mirrt) (1).st:=stilling;
      Repete(Mirrt) (1).tr:=fmax;
--*)
      IF (reps>1) AND (repmove.Til=fmax.Til) AND (repmove.Fra=fmax.Fra) THEN
        fmax.Typ:=MOVEx7;
        --$ IF False  WRITELN(s('!Find:x7!'));--$ ENDIF
      END IF;
    END IF;
--$ IF Test
--    WRITEF(s('Best: Vlu=')+l(fmax.Vlu)+s(' '));
--    ShowMove(fmax,Mirrt);
--    WRITELNF(0);
--$ ENDIF
  ELSE                  -- no moves, end
    fmax.Fra:=89;
    fmax.Til:=10;
    IF stilling(stOff+ 15)=wM THEN
      n:=15;
    ELSE
      n:=11;
      WHILE (n<89) AND (stilling(stOff+ n)<>wK) LOOP
        n := n + 1;
      END LOOP;
    END IF;
    IF CheckSkak(stilling,n,TRUE) THEN
      fmax.Typ:=MOVEmat;
      fmax.Vlu:=-16383;
--$ IF Test
--  WRITELNF(s('!MAT!'));
--$ ENDIF
    ELSE
      fmax.Typ:=MOVEpat;
      fmax.Vlu:=0;
--$ IF Test
--  WRITELNF(s('!PAT!'));
--$ ENDIF
    END IF;
  END IF;
  IF fmax.Vlu>16000 THEN fmax.Vlu := fmax.Vlu - 1; END IF;
  traek:=fmax;
  PL_PIG_CHESS_ENGINE_EVAL.Depth := PL_PIG_CHESS_ENGINE_EVAL.Depth - 1;
--$ IF Test
  
--$ ENDIF
END Find;
 
--    $ POP RangeChk POP OverflowChk POP StackChk POP ReturnChk
 
FUNCTION NEq(s1 in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE,s2 in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE) RETURN BOOLEAN IS
  n SIMPLE_INTEGER :=0;
BEGIN
  n:=11;
  WHILE (n<=HvisTur) AND (s1(n)=s2(n)) LOOP
    n := n + 1;
  END LOOP;
  RETURN(n<=HvisTur);
END NEq;
 
-- dybde:  (0,1,4,7,10,13)        ekstra: p.t. unused
PROCEDURE FindTrk(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, 
                  dybde SIMPLE_INTEGER,
                  ekstra SIMPLE_INTEGER,
                  Traek in out TRKDATA
                  ) IS
  TeoNvn CONSTANT VARCHAR2(30) := 'OPENINGS.TXT';
  X SIMPLE_INTEGER :=0;
  N SIMPLE_INTEGER :=0;
  p SIMPLE_INTEGER :=0;
  p2 SIMPLE_INTEGER :=0;
  Tnr SIMPLE_INTEGER :=0;
  fra SIMPLE_INTEGER :=0;
  til SIMPLE_INTEGER :=0;
  dyb SIMPLE_INTEGER :=0;
  OK BOOLEAN;
  SLUT BOOLEAN;
  --f File;
  RN       SIMPLE_INTEGER :=0;
  frqTotal SIMPLE_INTEGER :=0;
  Mcnt SIMPLE_INTEGER := 5;
---TYPE Ttype IS VARRAY(256) OF CHAR(1);-- 0..255 nu 1..256
--  TN Ttype; TL Ttype; 
  ch CHAR(1);
BEGIN
  IF not FirstW THEN
    INITIALIZE;
  END IF;
  STOPP:=FALSE;
  IF dybde=0 THEN
    til:=10;
    IF stilling(stOff+ HvisTur)<>bT THEN
      FOR fra in 11..88 LOOP
        IF (stilling(stOff+ fra)=wK) OR (stilling(stOff+ fra)=wM) THEN til:=fra; END IF;
      END LOOP;
    ELSE
      FOR fra in 11..88 LOOP
        IF (stilling(stOff+ fra)=bK) OR (stilling(stOff+ fra)=bM) THEN til:=fra; END IF;
      END LOOP;
    END IF;
    SkakDepth:=1; XchDepth:=1; MaxPosValGain:=20;
    Traek.Vlu:=QFind(stilling,10,20000,-20000,20,0,
                     CheckSkak(stilling,til,stilling(stOff+ HvisTur)<>bT),0,0,0,0);
  ELSE
--$ IF Stamp
--  W.Buf := '';
--  xcnt := 0;
--  Stamp(TRUE,Traek,'');
--$ ENDIF
    OK:=FALSE;
 
   -- Check om varianttræ har et ok forslag !!!!!!!!!!!!!!!!!!!!!!*)
    IF (TFra>10) AND (TTil>10) AND (TFra<89) AND (TTil<89) THEN
      IF (stilling(stOff+ HvisTur)=bT) AND (stilling(stOff+ TFra)<wA)
      OR (stilling(stOff+ HvisTur)<>bT) AND (stilling(stOff+ TFra)>'Z') THEN
        MaxTeori:=TraekNr+1;
        Traek.Fra:=TFra;
        Traek.Til:=TTil;
        Traek.Typ:=MOVEnormal;
        OK:=TRUE;
      END IF;
    END IF;

    IF NOT OK AND (TraekNr<TeoMaxTrk) AND TeoBook > 0 THEN
--WRT('BOOKADD? Book='||TeoBook||' TraekNr='||TraekNr||' TeoMaxTrk='||TeoMaxTrk);
        IF Teo.last IS NOT NULL THEN
          FOR X IN 1..Teo.last LOOP -- search for position
            IF Equal(Stilling,Teo(X)) THEN --  position found
              IF TeoT(X).last IS NOT NULL THEN
                frqTotal := 0;
                FOR moveCnt IN 1..TeoT(X).last LOOP
                  frqTotal := frqTotal + TeoT(X) (moveCnt).Vlu;
                END LOOP;
                IF frqTotal > 0 THEN 
                  --N:=TRUNC(dbms_random.value(1,TeoT(X).last+1));
                  RN := TRUNC(dbms_random.value(1,frqTotal+1));
                  N := 0;
                  frqTotal := 0;
                  FOR moveCnt IN 1..TeoT(X).last LOOP
                    N := N + 1;
                    frqTotal := frqTotal + TeoT(X) (moveCnt).Vlu;
                    IF frqTotal >= RN THEN EXIT; END IF;
                  END LOOP;
                  Traek:=TeoT(X) (N);
WRT('BOOK POS='||X||' RND='||N||' RN='||RN||' mv='||Traek.Fra||Traek.Til);
                  OK:=TRUE;
                  PL_PIG_CHESS_ENGINE_EVAL.Evals:=0;
                END IF;
              END IF;
            END IF;
          END LOOP;
        END IF;

    END IF;
 
    IF NOT OK THEN
      FirstCall:=TRUE;
      PL_PIG_CHESS_ENGINE_EVAL.Evals:=0;
      PL_PIG_CHESS_ENGINE_EVAL.Depth:=0;

      --AEM:=AEMproc; --!!!!!!!!!!!!!!!!!!!!!
      PL_PIG_CHESS_ENGINE_EVAL.PreProcessor(stilling);
 
 
  -- Max Positional Value Gain, used for cutoff 3:
  -- 0=77 20=94, 50=137, 100=140 so use:     20-50
  -- SkakDepth:    1-4
  -- XchDepth:     1-4
 
      dyb               := FLOOR((dybde-1) / 3) + 1;   -- 1-5   (1-3) 
      MaxEvals          := 96* dybde * dybde* dybde;--  SHIFT(192,dybde); -- dybde 1 ganger med 2 (384), dybde 2 med 4 (776) dybde 3 med 8 (1500)
      SkakDepth         := dyb + 2;--dyb + 2;  --MOD(dybde+1,3) + 0;         -- 2-4   (2)   
      XchDepth          := dyb + 1;--dyb + 1;  --MOD(dybde  ,3) + 1;         -- 1-3   (2)   
      MaxPosValGain     := (dyb+1)*10+5;--MOD(dybde  ,3) * 15 + 20;   -- 20-50 (35)  
      MaxStackDepth     := 11+dyb*2+FLOOR((SkakDepth+XchDepth) / 2);
--WRT('dybde='||dybde||' dyb='||dyb||' SkakDepth='||SkakDepth||' XchDepth='||XchDepth||' MaxPosValGain='||MaxPosValGain||' MaxStackDepth='||MaxStackDepth);  
--dybde=1 dyb=1 SkakDepth=2 XchDepth=2 MaxPosValGain=35 MaxStackDepth=15
--dybde=4 dyb=2 SkakDepth=2 XchDepth=2 MaxPosValGain=35 MaxStackDepth=17
--dybde=7 dyb=3 SkakDepth=2 XchDepth=2 MaxPosValGain=35 MaxStackDepth=19
      BlacksTurn:=stilling(stOff+ HvisTur)=bT;
      Find(stilling,dyb,20000,-20000,20,Traek,0,0,0,0);
      IF BlacksTurn THEN
        Traek.Fra:=MOD(Traek.Fra,10)+10*(9-FLOOR(Traek.Fra/10));
        Traek.Til:=MOD(Traek.Til,10)+10*(9-FLOOR(Traek.Til/10));
      END IF;
    END IF;
--$ IF Stamp
--  Stamp(FALSE,Traek,W.Buf);
--$ ENDIF
--$IF Test
--    WRITELNF(s('Evals=')+l(SkakBrainEval.Evals)+s(' Nodes=')+l(Nodes));
--    IF Traek.Typ=MOVETYPE{x7} THEN WRITELN(s('!Traek=x7!')); END IF;
--    Close(TestFil);
--$ENDIF
  END IF;
END FindTrk;
 
PROCEDURE GetNextQ(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, 
                   fra in out SIMPLE_INTEGER,
                   til in out SIMPLE_INTEGER,
                   retning in out SIMPLE_INTEGER,
                   MoveTyp in out MOVETYPE) IS
-- GetNext i en version der ikke respekterer skak, kun for GetMove(Quick)
  hvid BOOLEAN;
BEGIN
  IF stilling(stOff+ HvisTur)=wT THEN
    LOOP
      IF til>88 THEN
        LOOP -- find næste hvide brik
          fra := fra + 1;
          EXIT WHEN (fra>88) OR (stilling(stOff+ fra)>wA);
        END LOOP;
        til:=fra;
        retning:=0;
      END IF;
      IF fra<>89 THEN GetNextTil(stilling,fra,til,retning,MoveTyp); END IF;
      EXIT WHEN (til<>89) OR (fra=89);
    END LOOP;
  ELSE -- sort
    LOOP
      IF til>88 THEN
        LOOP
          fra := fra + 1;
          EXIT WHEN (fra>88) OR (stilling(stOff+ fra)<wA) AND (stilling(stOff+ fra)>bA);
        END LOOP;
        til:=fra;
        retning:=0;
      END IF;
      IF fra<>89 THEN GetNextTil(stilling,fra,til,retning,MoveTyp); END IF;
      EXIT WHEN (til<>89) OR (fra=89);
    END LOOP;
  END IF;
END GetNextQ;
 
-- 1'ste træk =1, Udfører træk hvis OK (fra<89)
-- Efter kald vil EatChar= den slagne brik (bBsSlLtdDTtR ellers spc)
PROCEDURE GetMove(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, 
                  t in out TRKDATA, 
                  MoveNr SIMPLE_INTEGER, 
                  Quick BOOLEAN) IS
  fra SIMPLE_INTEGER :=0;
  til SIMPLE_INTEGER :=0;
  retning SIMPLE_INTEGER :=0;
  n SIMPLE_INTEGER :=0;
  movetyp MOVETYPE :=MOVEnormal;
BEGIN
  fra:=10;
  til:=89;
  retning:=0;
  FOR n IN 1..MoveNr LOOP
    IF fra<89 THEN
      IF Quick THEN
        GetNextQ(stilling,fra,til,retning,movetyp);
      ELSE
        GetNext(stilling,fra,til,retning,movetyp);
      END IF;
--$IF Test
--    ELSE
--  d(s('GetMove: Not that many moves!!!'));
--  n:=MoveNr;
--$ENDIF
    END IF;
  END LOOP;
  IF fra<89 THEN  -- udfør træk
    IF SET_IN(MOVEslag,movetyp) THEN
      EatChar:=stilling(stOff+ til);
      IF EatChar=spc THEN
        IF stilling(stOff+ HvisTur)=bT THEN
          EatChar:=wP;
        ELSE
          EatChar:=bP;
        END IF;
      END IF;
    ELSE
      EatChar:=spc;
    END IF;
    DoMove(stilling,fra,til,movetyp);
  END IF;
  t.Fra:=fra;
  t.Til:=til;
  t.Typ:=movetyp;
  t.Vlu:=0;
  --$IF Test
--    d(s('GetMove: Fra=')+l(fra)+s(' Til=')+l(til)+s(' MoveNr=')+l(MoveNr));
  --$ENDIF
END GetMove;
 
PROCEDURE GetMoveNr(stilling in out PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE, 
                    p_Fra SIMPLE_INTEGER,
                    p_Til SIMPLE_INTEGER, 
                    MoveNr in out SIMPLE_INTEGER, 
                    Quick BOOLEAN) IS
  fra SIMPLE_INTEGER:=p_Fra;
  til SIMPLE_INTEGER:=p_Til;
  retning SIMPLE_INTEGER :=0;
  movetyp MOVETYPE :=MOVEnormal;
BEGIN
  fra:=10;
  til:=89;
  retning:=0;
  MoveNr:=0;
  LOOP
    MoveNr := MoveNr + 1;
    IF fra<89 THEN
      IF Quick THEN
        GetNextQ(stilling,fra,til,retning,movetyp);
      ELSE
        GetNext(stilling,fra,til,retning,movetyp);
      END IF;
  --$IF False
--    ELSE
--    d(s('GetMoveNr: Move not found!!!'));
  --$ENDIF
    END IF;
    EXIT WHEN (fra=p_Fra) AND (til=p_Til) OR (fra=89);
  END LOOP;
  --$IF False
  -- d(s('GetMoveNr: Fra=')+l(fra)+s(' Til=')+l(til)+s(' MoveNr=')+l(MoveNr));
  --$ENDIF
END GetMoveNr;
 
--  ValueCalc:ARRAY(bA..bR),(spc..bR) OF SIMPLE_INTEGER;
--  TYPE ValueCalcYtype IS VARRAY(53) OF SIMPLE_INTEGER; -- vcyoffset= -31 (spc..bR]
--  TYPE ValueCalcType  IS VARRAY(20) OF ValueCalcYtype; -- vcxoffset= -64 (bA..bR]
--  ValueCalc ValueCalcType;
--  nva.EXTEND(20); 
--  FOR i in 1..20 LOOP
--    nva(i):= ValueCalcYtype();
--    nva(i).EXTEND(53);
--  END LOOP;
  
PROCEDURE InitValueCalc IS
  --Fra CHAR(1);
  Fra_n SIMPLE_INTEGER :=0;
  --Til CHAR(1);
  Til_n SIMPLE_INTEGER :=0;
BEGIN
  --WRT('InitValueCalc');
  ValueCalc.extend(20);--allocate outer array as 1..20 (initialized empty by definition)
  FOR n in 1..20 LOOP
    ValueCalc(n):= ValueCalcYtype();--initialize outer array with empty inner array
    ValueCalc(n).extend(53); --allocate inner array as 1..53
  END LOOP;
  ValueCalc(vcxOff+ bA) (vcyOff+ bP):=PL_PIG_CHESS_ENGINE_EVAL.ValueB;
  ValueCalc(vcxOff+ bA) (vcyOff+ bQ):=PL_PIG_CHESS_ENGINE_EVAL.ValueD;
  ValueCalc(vcxOff+ bA) (vcyOff+ bE):=PL_PIG_CHESS_ENGINE_EVAL.ValueE;
  ValueCalc(vcxOff+ bA) (vcyOff+ bK):=PL_PIG_CHESS_ENGINE_EVAL.ValueK;
  ValueCalc(vcxOff+ bA) (vcyOff+ bB):=PL_PIG_CHESS_ENGINE_EVAL.ValueL;
  ValueCalc(vcxOff+ bA) (vcyOff+ bM):=PL_PIG_CHESS_ENGINE_EVAL.ValueM;
  ValueCalc(vcxOff+ bA) (vcyOff+ bC):=PL_PIG_CHESS_ENGINE_EVAL.ValueR;
  ValueCalc(vcxOff+ bA) (vcyOff+ bN):=PL_PIG_CHESS_ENGINE_EVAL.Value_S;
  ValueCalc(vcxOff+ bA) (vcyOff+ bR):=PL_PIG_CHESS_ENGINE_EVAL.ValueT;
  ValueCalc(vcxOff+ bA) (vcyOff+ spc):=0;
  FOR Fra_n IN bP..bR LOOP
     IF (Fra_n=bP) OR (Fra_n=bQ) OR (Fra_n=bE) OR (Fra_n=bK) OR (Fra_n=bB) OR (Fra_n=bM) OR (Fra_n=bC) OR (Fra_n=bN) OR (Fra_n=bR) THEN
      FOR Til_n in spc..bR LOOP
        IF (Til_n=spc) OR (Til_n=bP) OR (Til_n=bQ) OR (Til_n=bE) OR (Til_n=bK) OR (Til_n=bB) OR (Til_n=bM) OR (Til_n=bC) OR (Til_n=bN) OR (Til_n=bR) THEN
          IF (Fra_n=bK) OR (Fra_n=bM) THEN
            ValueCalc(vcxOff+ Fra_n) (vcyOff+ Til_n) := ValueCalc(vcxOff+ bA) (vcyOff+ Til_n);
          ELSE
            ValueCalc(vcxOff+ Fra_n) (vcyOff+ Til_n) := ValueCalc(vcxOff+ bA) (vcyOff+ Til_n) - ValueCalc(vcxOff+ bA) (vcyOff+ Fra_n);
          END IF;
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END InitValueCalc;

PROCEDURE InitTeo_Old IS -- Initialize small hardcoded opening-book.
  b1 INTEGER:=12;b2 INTEGER:=22;b3 INTEGER:=32;b4 INTEGER:=42;b5 INTEGER:=52;b6 INTEGER:=62;b7 INTEGER:=72;b8 INTEGER:=82;
  c1 INTEGER:=13;c2 INTEGER:=23;c3 INTEGER:=33;c4 INTEGER:=43;c5 INTEGER:=53;c6 INTEGER:=63;c7 INTEGER:=73;c8 INTEGER:=83;
  d1 INTEGER:=14;d2 INTEGER:=24;d3 INTEGER:=34;d4 INTEGER:=44;d5 INTEGER:=54;d6 INTEGER:=64;d7 INTEGER:=74;d8 INTEGER:=84;
  e1 INTEGER:=15;e2 INTEGER:=25;e3 INTEGER:=35;e4 INTEGER:=45;e5 INTEGER:=55;e6 INTEGER:=65;e7 INTEGER:=75;e8 INTEGER:=85;
  f1 INTEGER:=16;f2 INTEGER:=26;f3 INTEGER:=36;f4 INTEGER:=46;f5 INTEGER:=56;f6 INTEGER:=66;f7 INTEGER:=76;f8 INTEGER:=86;
  g1 INTEGER:=17;g2 INTEGER:=27;g3 INTEGER:=37;g4 INTEGER:=47;g5 INTEGER:=57;g6 INTEGER:=67;g7 INTEGER:=77;g8 INTEGER:=87;
  mvtN MOVETYPE:=MOVEnormal; mvtS MOVETYPE:=MOVEslag; mvtE MOVETYPE:=MOVEenpassant; mvtR MOVETYPE:=MOVErokade; -- normal, slag, enpassant, rokade 
  X INTEGER; Y INTEGER; st INTEGER;
PROCEDURE TeoS(StilNr SIMPLE_INTEGER,
               TrkNr SIMPLE_INTEGER,
               fra SIMPLE_INTEGER,
               til SIMPLE_INTEGER, 
               mvt MOVETYPE, 
               vlu SIMPLE_INTEGER) IS
  Trk TRKDATA;
BEGIN
  TeoT(1+ StilNr)(TrkNr).Fra:=fra; -- TeoT=0..TeoMax (5), 1..TeoMaxVar
  TeoT(1+ StilNr)(TrkNr).Til:=til;
  TeoT(1+ StilNr)(TrkNr).Typ:=mvt;
  TeoT(1+ StilNr)(TrkNr).Vlu:=vlu;
END TeoS;
BEGIN
  -- Create a small opening book 
  --for the first few moves: 6 opening moves each with 6 replies giving a total of 36 different (randomized) openings) 
  --WRT('InitTeo');
  DefStill.extend(121);--(121) OF CHAR(1); -- i PL/SQL er offset 11               -10..HvisTur: A1-H8=11-88, HvidSort=wT | bN 
  --WRT('InitTeo0');
  FOR n IN 1..121 LOOP
    DefStill(n) := edge;
  END LOOP;  
  --WRT('InitTeo1');
  still(DefStill,''); --start-position
  --Randomize;
  --WRT('InitTeo2');
  FOR X IN 0..TeoMaxPos LOOP
    Teo(1+ X):=DefStill;
    FOR Y IN 1..TeoMaxVar LOOP
      TeoT(1+ X)(Y).Fra:=11;--Fra=Til for unused slots.
      TeoT(1+ X)(Y).Til:=11;
      TeoT(1+ X)(Y).Typ:=mvtN;
      TeoT(1+ X)(Y).Vlu:=0;
    END LOOP;
  END LOOP;
  --WRT('InitTeo3');
  st:=0;
  TeoS(st,1,d2,d4,mvtN,0); -- start-position: d4,e4,c4,f4,b3,sf3
  TeoS(st,2,e2,e4,mvtN,0);
  TeoS(st,3,c2,c4,mvtN,0);
  TeoS(st,4,f2,f4,mvtN,0);
  TeoS(st,5,b2,b3,mvtN,0);
  TeoS(st,6,g1,f3,mvtN,0);
  st:=1;
  DoMove(Teo(1+ st), 24, 44, mvtN); -- d4: d5,g6,b6,sf6,f5,d6
  TeoS(st,1,d7,d5,mvtN,0);
  TeoS(st,2,g7,g6,mvtN,0);
  TeoS(st,3,b7,b6,mvtN,0);
  TeoS(st,4,g8,f6,mvtN,0);
  TeoS(st,5,f7,f5,mvtN,0);
  TeoS(st,6,d7,d6,mvtN,0);
  st := 2;
  DoMove(Teo(1+ st), 25, 45, mvtN); -- e4: e5,e6,c5,c6,d6,d5 
  TeoS(st,1,e7,e5,mvtN,0);
  TeoS(st,2,e7,e6,mvtN,0);
  TeoS(st,3,c7,c5,mvtN,0);
  TeoS(st,4,c7,c6,mvtN,0);
  TeoS(st,5,d7,d6,mvtN,0);
  TeoS(st,6,d7,d5,mvtN,0);
  st := 3;
  DoMove(Teo(1+ st), 23, 43, mvtN); -- c4: g6,f5,c5,e5,sf6,b6
  TeoS(st,1,g7,g6,mvtN,0);
  TeoS(st,2,f7,f5,mvtN,0);
  TeoS(st,3,c7,c5,mvtN,0);
  TeoS(st,4,e7,e5,mvtN,0);
  TeoS(st,5,g8,f6,mvtN,0);
  TeoS(st,6,b7,b6,mvtN,0);
  st := 4;
  DoMove(Teo(1+ st), 26, 46, mvtN); -- f4: d5,f5,b6,c5,sf6,g6 
  TeoS(st,1,d7,d5,mvtN,0);
  TeoS(st,2,f7,f5,mvtN,0);
  TeoS(st,3,b7,b6,mvtN,0);
  TeoS(st,4,c7,c5,mvtN,0);
  TeoS(st,5,g8,f6,mvtN,0);
  TeoS(st,6,g7,g6,mvtN,0);
  st := 5;
  DoMove(Teo(1+ st), 22, 32, mvtN); -- b3: d5,e5,sf6,c5,b6,sc6 
  TeoS(st,1,d7,d5,mvtN,0);
  TeoS(st,2,e7,e5,mvtN,0);
  TeoS(st,3,g8,f6,mvtN,0);
  TeoS(st,4,c7,c5,mvtN,0);
  TeoS(st,5,b7,b6,mvtN,0);
  TeoS(st,6,b8,c6,mvtN,0);
  st := 6;
  DoMove(Teo(1+ st), 17, 36, mvtN); -- sf3: d5,f5,sf6,c5,d6,g6
  TeoS(st,1,d7,d5,mvtN,0);
  TeoS(st,2,f7,f5,mvtN,0);
  TeoS(st,3,g8,f6,mvtN,0);
  TeoS(st,4,c7,c5,mvtN,0);
  TeoS(st,5,d7,d6,mvtN,0);
  TeoS(st,6,g7,g6,mvtN,0);
  --
  -- two 2-ply positions as example for expanding the book:
  st := 7;
  DoMove(Teo(1+ st), 17, 36, mvtN); -- sf3,
  DoMove(Teo(1+ st), 74, 54, mvtN); -- d5:  d4,g3
  TeoS(st,1,d2,d4,mvtN,0);
  TeoS(st,2,g2,g3,mvtN,0);
  st := 8;
  DoMove(Teo(1+ st), 17, 36, mvtN); -- sf3,
  DoMove(Teo(1+ st), 76, 56, mvtN); -- f5:  d4,c4
  TeoS(st,1,d2,d4,mvtN,0);
  TeoS(st,2,c2,c4,mvtN,0);
  --
  MaxTeori:=0;
END InitTeo_old;


PROCEDURE AddTeoMove(fr SIMPLE_INTEGER,ti SIMPLE_INTEGER, movetyp MOVETYPE, frequency SIMPLE_INTEGER) IS
   stillnr SIMPLE_INTEGER:=0;
   movenr  SIMPLE_INTEGER:=0;
BEGIN
  IF Teo.last IS NOT NULL THEN
    FOR n IN 1..Teo.last LOOP -- search for position
      IF Equal(DefStill,Teo(n)) THEN
        --WRT('AddTeoMove: found position');
        stillnr:= n;
        exit;
      END IF;
    END LOOP; 
  END IF;
  IF stillnr = 0 THEN -- allocate position
    --WRT('AddTeoMove: add position');
    Teo.extend;
    TeoT.extend;
    Teo(Teo.last)  := DefStill;
    TeoT(Teo.last) := TeoTTypeY();
    stillnr := Teo.last;
  END IF;
  IF TeoT(stillnr).last IS NOT NULL THEN
    FOR n IN 1..TeoT(stillnr).last LOOP -- search for move
      IF TeoT(stillnr) (n).fra=fr AND TeoT(stillnr) (n).til=ti THEN
         movenr := n;
         exit;
      END IF;
    END LOOP; 
  END IF;
  IF movenr = 0 THEN -- allocate and store move
    --WRT('AddTeoMove: add move '||fr||'-'||ti);
    TeoT(stillnr).extend;
    movenr := TeoT(stillnr).last;
    TeoT(stillnr) (movenr).Fra := fr;
    TeoT(stillnr) (movenr).Til := ti;
    TeoT(stillnr) (movenr).Vlu := frequency;
    TeoT(stillnr) (movenr).Typ := movetyp;
    TeoMoves := TeoMoves + 1;
  ELSE
    TeoT(stillnr) (movenr).Vlu := TeoT(stillnr) (movenr).Vlu + frequency;
  END IF;
END AddTeoMove;


PROCEDURE AddTeo(fromtostr VARCHAR2, frequency SIMPLE_INTEGER DEFAULT 1, maxmoves INTEGER DEFAULT 20) IS
  hj_str VARCHAR2(500) := REPLACE(REPLACE(REPLACE(UPPER(fromtostr),spc),'X'),'-');
  moves SIMPLE_INTEGER := 0;
  frti varchar2(4);
  fr SIMPLE_INTEGER:=0;
  ti SIMPLE_INTEGER:=0;
  mvt MOVETYPE:=0; 
BEGIN
  --WRT('AddTeo: '||hj_str);
  IF DefStill IS NULL THEN
    DefStill := PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE();
    DefStill.extend(121);
    FOR n IN 1..121 LOOP
      DefStill(n) := edge;
    END LOOP;  
  END IF;
  still(DefStill,''); --start-position
  WHILE length(hj_str) >= 4 and moves < maxmoves LOOP
    moves := moves + 1;
    IF moves > TeoMaxTrk THEN TeoMaxTrk := moves; END IF;
    frti := substr(hj_str,1,4);
    --WRT('AddTeo2: '||frti);
    hj_str := substr(hj_str,5);
    fr := substr(frti,2,1)*10 + ascii(substr(frti,1,1))-64;
    ti := substr(frti,4,1)*10 + ascii(substr(frti,3,1))-64;
    --
    IF fr=15 and (ti=17 OR ti=13) AND Defstill(stOff+ 15)=wM 
    OR fr=85 and (ti=87 OR ti=83) AND Defstill(stOff+ 85)=bM THEN 
      mvt := MOVErokade;
    ELSIF Defstill(stOff+ fr)=wP and Defstill(stOff+ ti)=spc and (ti-fr =  9 or ti-fr= 11)
       OR Defstill(stOff+ fr)=bP and Defstill(stOff+ ti)=spc and (ti-fr = -9 or ti-fr=-11) THEN
      mvt := MOVEenpassant;
    ELSIF Defstill(stOff+ fr)=wP and ti > 80 
       OR Defstill(stOff+ fr)=bP and ti < 20 THEN 
      mvt := MOVEpromotion;
    ELSE
      mvt := MOVEnormal;
    END IF;
    --
    AddTeoMove(fr,ti,mvt,frequency);
    --WRT('AddTeo3: '||fr||ti);
    DoMove(DefStill, fr, ti, mvt); 
  END LOOP;
--EXCEPTION WHEN OTHERS THEN
--   RAISE_APPLICATION_ERROR(-20001, 'AddTeo: '||fr||ti);
END AddTeo;

PROCEDURE InitTeo IS
BEGIN
 WRT('TeoBook '||TeoBook||' Init');
 IF FALSE THEN--test
   AddTeo('d2d4g8f6d4d5c7c5d5c6e7e6c6b7f8e7b7a8e8g8');--test en-passant, promotion and castling works in book.
 ELSIF TeoBook = 1 THEN
   -- MICRO-THEORY BOOK, 30 openings with 2 halfmoves, all playable. Weights that match frequency played by masters
  AddTeo('e2e4c7c5',43);  AddTeo('e2e4e7e5',39);  AddTeo('e2e4e7e6',14);  AddTeo('e2e4c7c6', 9);  AddTeo('e2e4d7d6', 3);  AddTeo('e2e4g7g6', 2);  AddTeo('e2e4d7d5', 1);  AddTeo('e2e4g8f6', 1);
  AddTeo('d2d4g8f6',55);  AddTeo('d2d4d7d5',24);  AddTeo('d2d4e7e6', 5);  AddTeo('d2d4f7f5', 2);  AddTeo('d2d4d7d6', 2);  AddTeo('d2d4g7g6', 1);
  AddTeo('g1f3g8f6',11);  AddTeo('g1f3d7d5', 9);  AddTeo('g1f3c7c5', 4);  AddTeo('g1f3g7g6', 1);  AddTeo('g1f3e7e6', 1);  AddTeo('g1f3f7f5', 1);
  AddTeo('c2c4e7e5', 7);  AddTeo('c2c4g8f6', 5);  AddTeo('c2c4e7e6', 3);  AddTeo('c2c4c7c5', 3);  AddTeo('c2c4c7c6', 1);  AddTeo('c2c4g7g6', 1);
  AddTeo('g2g3d7d5', 1);  
  AddTeo('e2e3g8f6', 1);  
  AddTeo('b2b3e7e5', 1);  
  AddTeo('f2f4d7d5', 1);  
 ELSIF TeoBook = 2 THEN
   -- MINI-THEORY BOOK, 178 openings with 2-8 halfmoves, all playable.
   -- They are weighted to match frequency played by masters
  AddTeo('e2e4c7c5g1f3d7d6d2d4');             AddTeo('e2e4c7c5g1f3b8c6d2d4');             AddTeo('e2e4c7c5g1f3e7e6d2d4');         AddTeo('e2e4c7c5b1c3');
  AddTeo('e2e4e7e5g1f3b8c6f1b5');             AddTeo('e2e4e7e5g1f3b8c6f1b5a7a6b5a4g8f6'); AddTeo('e2e4e7e5g1f3b8c6f1b5a7a6b5c6'); AddTeo('e2e4e7e5g1f3b8c6f1b5g8f6e1g1');
  AddTeo('e2e4e7e5g1f3b8c6f1b5f7f5');         AddTeo('e2e4e7e5g1f3b8c6f1b5d7d6');         AddTeo('e2e4e7e5g1f3b8c6f1c4f8c5');     AddTeo('e2e4e7e5g1f3b8c6f1c4g8f6');
  AddTeo('e2e4e7e5g1f3g8f6f3e5d7d6');         AddTeo('e2e4e7e5g1f3g8f6b1c3');             AddTeo('e2e4e7e5g1f3g8f6d2d4');         AddTeo('e2e4e7e5b1c3');
  AddTeo('e2e4e7e5f2f4');                     AddTeo('e2e4e7e5d2d4');                     AddTeo('e2e4e7e5f1c4');                 AddTeo('e2e4e7e6d2d4d7d5b1c3g8f6');
  AddTeo('e2e4e7e6d2d4d7d5b1c3f8b4');         AddTeo('e2e4e7e6d2d4d7d5b1c3d5e4');         AddTeo('e2e4e7e6d2d4d7d5b1d2');         AddTeo('e2e4e7e6d2d4d7d5e4e5');
  AddTeo('e2e4e7e6d2d4d7d5e4d5');             AddTeo('e2e4e7e6g1f3');                     AddTeo('e2e4e7e6b1c3');                 AddTeo('e2e4e7e6d2d3');
  AddTeo('e2e4c7c6d2d4d7d5b1c3');             AddTeo('e2e4c7c6d2d4d7d5e4e5');             AddTeo('e2e4c7c6d2d4d7d5e4d5');         AddTeo('e2e4c7c6g1f3');
  AddTeo('e2e4c7c6b1c3');                     AddTeo('e2e4d7d5e4d5d8d5b1c3d5a5');         AddTeo('e2e4d7d5e4d5d8d5b1c3d5d8');     AddTeo('e2e4d7d5e4d5d8d5b1c3d5d6');
  AddTeo('e2e4d7d5e4d5g8f6');                 AddTeo('e2e4d7d5b1c3');                     AddTeo('e2e4d7d6d2d4g8f6b1c3');         AddTeo('e2e4d7d6d2d4g7g6');
  AddTeo('e2e4d7d6d2d4c7c6');                 AddTeo('e2e4d7d6g1f3');                     AddTeo('e2e4d7d6b1c3');                 AddTeo('e2e4g7g6d2d4f8g7b1c3');
  AddTeo('e2e4g7g6d2d4f8g7g1f3');             AddTeo('e2e4g7g6d2d4f8g7c2c4');             AddTeo('e2e4g7g6b1c3');                 AddTeo('e2e4g7g6g1f3');
  AddTeo('e2e4g8f6e4e5f6d4d2d4');             AddTeo('e2e4g8f6e4e5f6d5c2c4');             AddTeo('e2e4g8f6b1c3');                 AddTeo('e2e4b8c6d2d4');
  AddTeo('e2e4b8c6g1f3');                     AddTeo('d2d4g8f6c2c4e7e6b1c3f8b4e2e3');     AddTeo('d2d4g8f6c2c4e7e6b1c3f8b4d1c2'); AddTeo('d2d4g8f6c2c4e7e6b1c3d7d5');
  AddTeo('d2d4g8f6c2c4e7e6g1f3b7b6');         AddTeo('d2d4g8f6c2c4e7e6g1f3d7d5');         AddTeo('d2d4g8f6c2c4e7e6g1f3f8b4');     AddTeo('d2d4g8f6c2c4e7e6g2g3');
  AddTeo('d2d4g8f6c2c4g7g6b1c3f8g7e2e4d7d6'); AddTeo('d2d4g8f6c2c4g7g6b1c3f8g7e2e4e8g8'); AddTeo('d2d4g8f6c2c4g7g6b1c3d7d5');     AddTeo('d2d4g8f6c2c4g7g6g1f3');
  AddTeo('d2d4g8f6c2c4g7g6g2g3');             AddTeo('d2d4g8f6c2c4g7g6f2f3');             AddTeo('d2d4g8f6c2c4c7c5');             AddTeo('d2d4g8f6c2c4e7e5');
  AddTeo('d2d4g8f6c2c4d7d6');                 AddTeo('d2d4g8f6c2c4d7d5');                 AddTeo('d2d4g8f6g1f3g7g6c2c4');         AddTeo('d2d4g8f6g1f3g7g6g2g3');
  AddTeo('d2d4g8f6g1f3g7g6c1g5');             AddTeo('d2d4g8f6g1f3g7g6c1f4');             AddTeo('d2d4g8f6g1f3e7e6c2c4');         AddTeo('d2d4g8f6g1f3e7e6c1g5');
  AddTeo('d2d4g8f6g1f3e7e6e2e3');             AddTeo('d2d4g8f6g1f3e7e6g2g3');             AddTeo('d2d4g8f6g1f3d7d5');             AddTeo('d2d4g8f6g1f3c7c5');
  AddTeo('d2d4g8f6c1g5f6e4');                 AddTeo('d2d4g8f6c1g5e7e6');                 AddTeo('d2d4g8f6e2e3');                 AddTeo('d2d4g8f6b1c3');
  AddTeo('d2d4d7d5c2c4c7c6g1f3g8f6b1c3e7e6'); AddTeo('d2d4d7d5c2c4c7c6g1f3g8f6b1c3d5c4'); AddTeo('d2d4d7d5c2c4c7c6g1f3g8f6e2e3'); AddTeo('d2d4d7d5c2c4c7c6g1f3e7e6');
  AddTeo('d2d4d7d5c2c4c7c6b1c3');             AddTeo('d2d4d7d5c2c4c7c6c4d5');             AddTeo('d2d4d7d5c2c4e7e6');             AddTeo('d2d4d7d5c2c4d5c4');
  AddTeo('d2d4d7d5g1f3g8f6c2c4e7e6');         AddTeo('d2d4d7d5g1f3g8f6c2c4c7c6');         AddTeo('d2d4d7d5g1f3g8f6c2c4d5c4');     AddTeo('d2d4d7d5g1f3g8f6e2e3');
  AddTeo('d2d4d7d5g1f3g8f6c1f4');             AddTeo('d2d4d7d5g1f3g8f6c1g5');             AddTeo('d2d4d7d5g1f3c7c6');             AddTeo('d2d4d7d5g1f3e7e6');
  AddTeo('d2d4d7d5e2e3');                     AddTeo('d2d4d7d5c1g5');                     AddTeo('d2d4d7d5b1c3');                 AddTeo('d2d4d7d5c1f4');
  AddTeo('d2d4d7d5c2c3');                     AddTeo('d2d4d7d5e2e4');                     AddTeo('d2d4e7e6c2c4d7d5');             AddTeo('d2d4e7e6c2c4g8f6');
  AddTeo('d2d4e7e6c2c4f7f5');                 AddTeo('d2d4e7e6g1f3');                     AddTeo('d2d4e7e6e2e4');                 AddTeo('d2d4c7c5d4d5g8f6');
  AddTeo('d2d4c7c5d4d5d7d6');                 AddTeo('d2d4c7c5d4d5e7e5');                 AddTeo('d2d4c7c5g1f3');                 AddTeo('d2d4d7d6c2c4');
  AddTeo('d2d4d7d6g1f3');                     AddTeo('d2d4d7d6e2e4');                     AddTeo('d2d4g7g6');                     AddTeo('d2d4g7g6c2c4');
  AddTeo('d2d4g7g6g1f3');                     AddTeo('d2d4g7g6e2e4');                     AddTeo('d2d4c7c6c2c4');                 AddTeo('d2d4c7c6g1f3');
  AddTeo('d2d4c7c6e2e4');                     AddTeo('d2d4f7f5g1f3');                     AddTeo('d2d4f7f5c2c4');                 AddTeo('d2d4f7f5g2g3');
  AddTeo('d2d4f7f5c1g5');                     AddTeo('d2d4e7e5');                         AddTeo('d2d4b8c6');                     AddTeo('d2d4b7b6');
  AddTeo('g1f3g8f6c2c4');                     AddTeo('g1f3g8f6g2g3');                     AddTeo('g1f3g8f6d2d4');                 AddTeo('g1f3d7d5d2d4');
  AddTeo('g1f3d7d5g2g3');                     AddTeo('g1f3d7d5c2c4');                     AddTeo('g1f3c7c5');                     AddTeo('g1f3g7g6');
  AddTeo('g1f3d7d6');                         AddTeo('g1f3e7e6');                         AddTeo('g1f3c7c6');                     AddTeo('g1f3b8c6');
  AddTeo('c2c4g8f6b1c3');                     AddTeo('c2c4g8f6g2g3');                     AddTeo('c2c4g8f6d2d4');                 AddTeo('c2c4g8f6g1f3');
  AddTeo('c2c4e7e5b1c3');                     AddTeo('c2c4e7e5g2g3');                     AddTeo('c2c4e7e6');                     AddTeo('c2c4c7c5');
  AddTeo('c2c4c7c6');                         AddTeo('c2c4g7g6');                         AddTeo('c2c4d7d6');                     AddTeo('c2c4d7d5');
  AddTeo('c2c4f7f5');                         AddTeo('g2g3d7d5f1g2c7c6');                 AddTeo('g2g3d7d5f1g2g8f6');             AddTeo('g2g3g8f6');
  AddTeo('g2g3g7g6');                         AddTeo('g2g3e7e5');                         AddTeo('g2g3c7c6');                     AddTeo('g2g3c7c5');
  AddTeo('b1c3d7d5e2e4');                     AddTeo('b1c3d7d5g1f3');                     AddTeo('b1c3g8f6');                     AddTeo('b1c3c7c5');
  AddTeo('e2e3d7d5');                         AddTeo('e2e3e7e5');                         AddTeo('e2e3g8f6');                     AddTeo('e2e3c7c5');
  AddTeo('e2e3g7g6');                         AddTeo('b2b3e7e5');                         AddTeo('b2b3d7d5');                     AddTeo('b2b3g8f6');
  AddTeo('f2f4d7d5');                         AddTeo('f2f4e7e5');
 END IF;
 WRT('X='||TeoMaxTrk||spc||Teo.last||' moves='||TeoMoves);
 MaxTeori:=0;
END InitTeo;

PROCEDURE InitRetn IS
  --allocates and initiates the movetable array. Flyttet fra BrainX
BEGIN
--
  retn.extend(58);--ARRAY[bP..wR] pl/sql rxOff = -65 CHR()
  FOR n in 1..58 LOOP
      retn(n) := retnTypeY();
      retn(n).extend(63);--ARRAY[-31..31] pl/sql ryOff = 32
  END LOOP;
  --
  --initiate movetable
  retn(rxOff+ wR) (ryOff+ MaxDistance) := 8;--white rook
  retn(rxOff+ wR) (ryOff+   0):=-10;
  retn(rxOff+ wR) (ryOff+ -10):= -1;
  retn(rxOff+ wR) (ryOff+  -1):=  1;
  retn(rxOff+ wR) (ryOff+   1):= 10;
  retn(rxOff+ wR) (ryOff+  10):=  0;

  retn(rxOff+ bR):=retn(rxOff+ wR);-- black = white rook

  retn(rxOff+ wC) (ryOff+ MaxDistance):=8;--white rook castling possible
  retn(rxOff+ wC) (ryOff+   0):= 10;
  retn(rxOff+ wC) (ryOff+  10):= -1;
  retn(rxOff+ wC) (ryOff+  -1):=  1;
  retn(rxOff+ wC) (ryOff+   1):=  0;

  retn(rxOff+ bC) (ryOff+ MaxDistance):=8;--black rook castling possible
  retn(rxOff+ bC) (ryOff+   0):=-10;
  retn(rxOff+ bC) (ryOff+ -10):= -1;
  retn(rxOff+ bC) (ryOff+  -1):=  1;
  retn(rxOff+ bC) (ryOff+   1):=  0;

  retn(rxOff+ wN) (ryOff+ MaxDistance):=1; --white knight
  retn(rxOff+ wN) (ryOff+   0):=-21;
  retn(rxOff+ wN) (ryOff+ -21):=-19;
  retn(rxOff+ wN) (ryOff+ -19):=-12;
  retn(rxOff+ wN) (ryOff+ -12):= -8;
  retn(rxOff+ wN) (ryOff+  -8):=  8;
  retn(rxOff+ wN) (ryOff+   8):= 12;
  retn(rxOff+ wN) (ryOff+  12):= 19;
  retn(rxOff+ wN) (ryOff+  19):= 21;
  retn(rxOff+ wN) (ryOff+  21):=  0;
  retn(rxOff+ bN):=retn(rxOff+ wN);--black = white knight

  retn(rxOff+ wB) (ryOff+ MaxDistance):=8;--white bishop
  retn(rxOff+ wB) (ryOff+   0):=-11;
  retn(rxOff+ wB) (ryOff+ -11):= -9;
  retn(rxOff+ wB) (ryOff+  -9):=  9;
  retn(rxOff+ wB) (ryOff+   9):= 11;
  retn(rxOff+ wB) (ryOff+  11):=  0;
  retn(rxOff+ bB):=retn(rxOff+ wB);--black = white bishop

  retn(rxOff+ wQ) (ryOff+ MaxDistance):=8;--white queen
  retn(rxOff+ wQ) (ryOff+   0):=-11;
  retn(rxOff+ wQ) (ryOff+ -11):=-10;
  retn(rxOff+ wQ) (ryOff+ -10):= -9;
  retn(rxOff+ wQ) (ryOff+  -9):= -1;
  retn(rxOff+ wQ) (ryOff+  -1):=  1;
  retn(rxOff+ wQ) (ryOff+   1):=  9;
  retn(rxOff+ wQ) (ryOff+   9):= 10;
  retn(rxOff+ wQ) (ryOff+  10):= 11;
  retn(rxOff+ wQ) (ryOff+  11):=  0;
  retn(rxOff+ bQ):=retn(rxOff+ wQ);--black = white queen

  retn(rxOff+ wM) (ryOff+ MaxDistance):=1;-- white king castling possible
  retn(rxOff+ wM) (ryOff+   0):= -2;
  retn(rxOff+ wM) (ryOff+  -2):= -1;
  retn(rxOff+ wM) (ryOff+  -1):=  1;
  retn(rxOff+ wM) (ryOff+   1):=  2;
  retn(rxOff+ wM) (ryOff+   2):=  9;
  retn(rxOff+ wM) (ryOff+   9):= 10;
  retn(rxOff+ wM) (ryOff+  10):= 11;
  retn(rxOff+ wM) (ryOff+  11):=  0;
  retn(rxOff+ bM) (ryOff+ MaxDistance):=1;-- black king castling possible
  retn(rxOff+ bM) (ryOff+   0):= -2;
  retn(rxOff+ bM) (ryOff+  -2):= -1;
  retn(rxOff+ bM) (ryOff+  -1):=  1;
  retn(rxOff+ bM) (ryOff+   1):=  2;
  retn(rxOff+ bM) (ryOff+   2):=-11;
  retn(rxOff+ bM) (ryOff+ -11):=-10;
  retn(rxOff+ bM) (ryOff+ -10):= -9;
  retn(rxOff+ bM) (ryOff+  -9):=  0;

  retn(rxOff+ wK) (ryOff+ MaxDistance):=1;-- white king
  retn(rxOff+ wK) (ryOff+   0):=-11;
  retn(rxOff+ wK) (ryOff+ -11):=-10;
  retn(rxOff+ wK) (ryOff+ -10):= -9;
  retn(rxOff+ wK) (ryOff+  -9):= -1;
  retn(rxOff+ wK) (ryOff+  -1):=  1;
  retn(rxOff+ wK) (ryOff+   1):=  9;
  retn(rxOff+ wK) (ryOff+   9):= 10;
  retn(rxOff+ wK) (ryOff+  10):= 11;
  retn(rxOff+ wK) (ryOff+  11):=  0;
  retn(rxOff+ bK):=retn(rxOff+ wK);-- black = white king

  retn(rxOff+ wP) (ryOff+ MaxDistance):=1;-- white pawn
  retn(rxOff+ wP) (ryOff+   0):=  9;
  retn(rxOff+ wP) (ryOff+   9):= 10;
  retn(rxOff+ wP) (ryOff+  10):= 11;
  retn(rxOff+ wP) (ryOff+  11):= 20;
  retn(rxOff+ wP) (ryOff+  20):=-11;
  retn(rxOff+ wP) (ryOff+ -11):=-10;-- -11..-9 promote to rook (til-20) 
  retn(rxOff+ wP) (ryOff+ -10):= -9;
  retn(rxOff+ wP) (ryOff+  -9):=-21;
  retn(rxOff+ wP) (ryOff+ -21):=-20;-- -21..-6 promote to knight (til-30) 
  retn(rxOff+ wP) (ryOff+ -20):=-19;
  retn(rxOff+ wP) (ryOff+ -19):=-31;
  retn(rxOff+ wP) (ryOff+ -31):=-30;-- -7..-9 promote to bishop (til-40) 
  retn(rxOff+ wP) (ryOff+ -30):=-29;
  retn(rxOff+ wP) (ryOff+ -29):=  0;
  retn(rxOff+ wE):=retn(rxOff+ wP);-- white enpassant pawn= white pawn
  retn(rxOff+ wE) (ryOff+ 11) :=  0;
  retn(rxOff+ bP) (ryOff+ MaxDistance):=1;-- black pawn
  retn(rxOff+ bP) (ryOff+   0):= -9;
  retn(rxOff+ bP) (ryOff+  -9):=-10;
  retn(rxOff+ bP) (ryOff+ -10):=-11;
  retn(rxOff+ bP) (ryOff+ -11):=-20;
  retn(rxOff+ bP) (ryOff+ -20):= 11;
  retn(rxOff+ bP) (ryOff+  11):= 10;--  11..9 promote to rook (til+20) 
  retn(rxOff+ bP) (ryOff+  10):=  9;
  retn(rxOff+ bP) (ryOff+   9):= 21;
  retn(rxOff+ bP) (ryOff+  21):= 20;-- 21..19 promote to knight (til+30) 
  retn(rxOff+ bP) (ryOff+  20):= 19;
  retn(rxOff+ bP) (ryOff+  19):= 31;
  retn(rxOff+ bP) (ryOff+  31):= 30;-- 31..29 promote to bishop (til+40) 
  retn(rxOff+ bP) (ryOff+  30):= 29;
  retn(rxOff+ bP) (ryOff+  29):=  0;
  retn(rxOff+ bE):=retn(rxOff+ bP);-- black enpassant pawn= black pawn
  retn(rxOff+ bE) (ryOff+ -11):=  0;
END InitRetn; 
  
  

PROCEDURE Initialize IS
BEGIN
  IF not FirstW THEN
    FirstW:=TRUE;
    PL_PIG_CHESS_ENGINE_EVAL.INITIALIZE;
    --
    --
    repete.extend(2); -- (FALSE..TRUE) now 1=FALSE, 2=TRUE 
    FOR n in 1..2 LOOP
      repete(n) := RepeteYtype();
      repete(n).extend(HisMax); --20
    END LOOP;    
    --
    InitRetn;
    InitTeo;
    InitValueCalc;
    --WRT('Initialize SB');
  ELSE
    NULL;
    --WRT('Initialize SB SKIP');
  END IF;
END Initialize;
END;
/


DROP PACKAGE BODY PL_PIG_CHESS_INTERFACE;

CREATE OR REPLACE PACKAGE BODY PL_PIG_CHESS_INTERFACE AS
--
-- PL_PIG_CHESS_INTERFACE v 0.92
--
-- Interface for play with PL_PIG_CHESS_ENGINE using DBMS_OUTPUT
--
position          PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE := PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE();
InitializedStatic BOOLEAN := FALSE; -- any call will make the static initializations and set this flag.
WhiteSide         INTEGER;          -- 0=human, 2=low,  4=medium, 6=high (engine strength/timeusage, 8 and 10 is possible, but not recommended)
BlackSide         INTEGER;          -- 0=human, 2=low,  4=medium, 6=high (engine strength/timeusage, 8 and 10 is possible, but not recommended)
BlackToMove       BOOLEAN;          -- FALSE = WhiteToMove
InteractionMode   INTEGER:=1;       -- 0+1 =dbms_output, 2=table, 3=tables(asyncronous)
TheoryMode        INTEGER;          -- 0= no theory, 1=internal theory (random play 2 ply, 30 lines), 2= Mini-book  178 x (2->8)
EvTot             INTEGER:=0;       -- Total count of evals
Board             BOOLEAN := TRUE;  -- Show Board in output
trk               PL_PIG_CHESS_ENGINE.TRKDATA;   -- last move
MOVETEXT          VARCHAR2(20);     -- last move in full-text

PROCEDURE WR(s VARCHAR2) IS
BEGIN
  IF InteractionMode in (0,1) THEN
    dbms_output.put_line(s);
  ELSIF   InteractionMode=2 THEN
    NULL;
  ELSIF  InteractionMode=3 THEN
    NULL;
  END IF;
END WR;

FUNCTION SET_IN(members BINARY_INTEGER, setM BINARY_INTEGER) return BOOLEAN IS
BEGIN -- IN: member of set (M n N)
RETURN UTL_RAW.CAST_TO_BINARY_INTEGER(UTL_RAW.bit_and(UTL_RAW.CAST_FROM_BINARY_INTEGER(members),UTL_RAW.CAST_FROM_BINARY_INTEGER(setM)))=members;
END;

FUNCTION MOVETXT( trk PL_PIG_CHESS_ENGINE.TRKDATA, piece VARCHAR2 DEFAULT NULL, english BOOLEAN DEFAULT TRUE) RETURN varchar2 IS
-- converts internal format for a move to a text-format
  res VARCHAR2(20);
  x SIMPLE_INTEGER:=0;
  y SIMPLE_INTEGER:=0;
BEGIN
  IF english THEN
    CASE upper(piece)
      WHEN 'T' THEN res := 'R';
      WHEN 'S' THEN res := 'N';
      WHEN 'L' THEN res := 'B';
      WHEN 'B' THEN res := '';--'P' but don't show
      WHEN 'E' THEN res := '';--'P' but don't show
      WHEN 'D' THEN res := 'Q';
      WHEN 'M' THEN res := 'K';
      ELSE          res := upper(piece);
    END CASE;
  ELSE
    IF    upper(piece) = 'M' then res := 'K';
    ELSIF upper(piece) = 'B' then res := '';--'B' but don't show
    ELSIF upper(piece) = 'E' then res := '';--'B' but don't show
    ELSE                          res := upper(piece);
    END IF;
  END IF;
  x := MOD(Trk.Fra,10);
  y := FLOOR(Trk.Fra/10);
  res := res||chr(x+96)||y;
  IF SET_IN(PL_PIG_CHESS_ENGINE.MOVEslag,Trk.Typ) THEN
    res := res||'x';
  ELSE
    res := res||'-';
  END IF;
  x := MOD(Trk.Til,10);
  y := FLOOR(Trk.Til/10);
  res := res||chr(x+96)||y;
  IF SET_IN(PL_PIG_CHESS_ENGINE.MOVErokade,Trk.Typ) THEN  
    IF x=7 THEN res :='o-o'; else res := 'o-o-o'; END IF;
  END IF;
  IF SET_IN(PL_PIG_CHESS_ENGINE.MOVEmat,Trk.Typ) THEN
    res := res||'++';  
  ELSIF SET_IN(PL_PIG_CHESS_ENGINE.MOVEpat,Trk.Typ) THEN  
    IF english THEN
      res := res||'(pat)';  
    ELSE
      res := res||'(stalemate)';  
    END IF;
  ELSIF SET_IN(PL_PIG_CHESS_ENGINE.MOVEskak,Trk.Typ) THEN  
    res := res||'+';  
  ELSIF SET_IN(PL_PIG_CHESS_ENGINE.MOVEpromotion,Trk.Typ) THEN  
    IF english THEN
      res := res||'(d)';   
    ELSE
      res := res||'(q)';   
    END IF;
  END IF;
  return res;
END MOVETXT;  

FUNCTION SHORT(mvtxt VARCHAR2, Multiple BOOLEAN DEFAULT FALSE) RETURN VARCHAR2 IS
--Makes a short-version of a movetext so it can be compared to test-suites.
 hj_mvtxt VARCHAR2(20);
BEGIN
   hj_mvtxt := replace(replace(replace(mvtxt,'+'),'(d)'),'(q)');
   IF length(hj_mvtxt)=6 THEN 
     IF INSTR(hj_mvtxt,'x')=4 THEN
       hj_mvtxt := substr(hj_mvtxt,1,1)||substr(hj_mvtxt,4);
     ELSE
       hj_mvtxt := substr(hj_mvtxt,1,1)||substr(hj_mvtxt,5);
     END IF;
   ELSIF length(hj_mvtxt)=5 AND INSTR(hj_mvtxt,'-')=3 THEN 
     hj_mvtxt := substr(hj_mvtxt,4);
   ELSIF length(hj_mvtxt)=5 AND INSTR(hj_mvtxt,'x')=3 THEN 
     hj_mvtxt := substr(hj_mvtxt,1,1)||substr(hj_mvtxt,3);
   END IF;
   RETURN hj_mvtxt;
END SHORT;

PROCEDURE OUTPUT_POSITION(english BOOLEAN DEFAULT TRUE) IS
  s VARCHAR2(80);
  ch CHAR(1);
BEGIN
  IF BOARD THEN
    WR('.  _______________________________');
    FOR yy IN 1..8 LOOP
      s :=' '||to_char(9-yy)||' | ';
      FOR xx IN 1..8 LOOP
        s := s||chr(position(PL_PIG_CHESS_ENGINE.stOff+ xx+10*(9-yy)))||' | ';
      END LOOP;
      IF english THEN --english version will not show castling-rights and en-passant.
        s := TRANSLATE(s,'BbEeLlSsDdTt',
                         'PpPpBbNnQqRr');
      END IF;
      WR(s);
      WR('.  -------------------------------');
    END LOOP;
    ch := chr(position(PL_PIG_CHESS_ENGINE.stOff+ PL_PIG_CHESS_ENGINE_EVAL.HvisTur ));
    WR('.   A   B   C   D   E   F   G   H   '''||CASE WHEN english THEN CASE when ch='S' THEN 'B' ELSE 'W' END ELSE ch END||'''');
  END IF;
END OUTPUT_POSITION;


FUNCTION EPD_STR(operationlist  VARCHAR2 DEFAULT NULL) RETURN varchar2 IS
-- returns the current position in EPD (or FEN) format:
-- EPD_STR('co "comment";')
-- or in FEN format:
-- EPD_STR('0 1')
  hj_list VARCHAR2(200):=operationlist;
BEGIN 
  IF hj_list IS NULL THEN
    hj_list := ' bm '||SHORT(MOVETEXT)||'; id "'||Trk.vlu||'"; c0 "'||PL_PIG_CHESS_ENGINE_EVAL.Evals||'";'; 
  END IF;
  RETURN PL_PIG_CHESS_ENGINE.STILLING_TO_EPD(position, hj_list);
END; 

FUNCTION INV_EPD(epdfenstr VARCHAR2) RETURN VARCHAR2 IS
-- returns a  EPD (or FEN) position reversed
rev varchar2(256);
reo varchar2(256);
rmv varchar2(256):='';
rtx varchar2(256):='';
P integer;
G integer;
BEGIN
  P := instr(epdfenstr,' ');
  rev := TRANSLATE(substr(epdfenstr,1,p),'012345678RNBQKPrnbqkp/ ',
                                         '012345678rnbqkpRNBQKP//');
  FOR n IN 1..8 LOOP
    G := instr(rev,'/');
    IF n=1 THEN
      reo := substr(rev,1,G-1)||' ';
    ELSE
      reo := substr(rev,1,G)||reo;
    END IF;
    rev := substr(rev,G+1);
  END LOOP;
  --
  IF UPPER(substr(epdfenstr,P+1,1))='B' THEN
    reo:= reo||'w ';
  ELSE
    reo:= reo||'b ';
  END IF;
  G := instr(epdfenstr,'"');
  IF G=0 THEN
    rmv := substr(epdfenstr,P+3);
  ELSE
    rtx := substr(epdfenstr, G-1);
    rmv := substr(epdfenstr,P+3, G-(P+3)-1);
  END IF;
  rmv :=  TRANSLATE(rmv,'12345678',
                        '87654321');
  RETURN reo||rmv||rtx;
END;
--
--
FUNCTION POSITION_STR(english BOOLEAN DEFAULT TRUE) RETURN varchar2 IS 
-- makes the internal position array format to the internal string format for a position
  s VARCHAR2(80):='';--str65
  ch CHAR(1);
BEGIN
  FOR yy IN 1..8 LOOP
    FOR xx IN 1..8 LOOP
      s := s||chr(position(PL_PIG_CHESS_ENGINE.stOff+ xx+10*(9-yy)));
    END LOOP;
  END LOOP;
  ch := chr(position(PL_PIG_CHESS_ENGINE.stOff+ PL_PIG_CHESS_ENGINE.HvisTur ));
  IF english THEN
    s := TRANSLATE(SUBSTR(s,1,64),'BbLlSsDdTtRr',
                                  'PpBbNnQqRrCc')||case when ch='S' THEN 'B' else 'W' end;
    return s;
  ELSE
    return s||ch;
  END IF;
END POSITION_STR;
--
--
PROCEDURE NEW_GAME(
  White INTEGER  DEFAULT 2,                -- 0=human, 2=low,  4=medium, 6=high (engine strength/timeuse)
  Black INTEGER  DEFAULT 0,                -- 0=human, 2=low,  4=medium, 6=high (engine strength/timeuse)
  STARTPOSITION      VARCHAR2 DEFAULT NULL,  -- NULL= chess startposition. A position in FEN, EPD or the internal POSITIONSTR format (english version supported).
  p_TheoryMode       INTEGER  DEFAULT 0,     -- 0= no theory, 1=internal theory (random play 2 ply, 16 lines), 2= internal opening book (random play of about 3000 opening-lines)   
  p_InteractionMode  INTEGER  DEFAULT 1      -- 0=dbms_output (moves only) 1=dbms_output (with positions), 2=table, 3=tables(asyncronous)
  ) IS
BEGIN
  IF White > 10 then
    WhiteSide       := 10;--internal limit
  ELSE
    WhiteSide       := White;
  END IF;
  IF Black > 10 then
    BlackSide       := 10;--internal limit
  ELSE 
    BlackSide       := Black;
  END IF;
  TheoryMode      := p_TheoryMode;
  InteractionMode := p_InteractionMode;
  IF InteractionMode = 1 THEN
    Board := TRUE;
  ELSIF InteractionMode = 0 THEN
    Board := FALSE;
  END IF;
  WR('Game started '||to_char(sysdate,'dd/mm-yyyy hh24:mi:ss'));
  PL_PIG_CHESS_ENGINE.Initialize;
  IF NOT InitializedStatic THEN
    position.extend(121);--(121) OF CHAR(1); /* i PL/SQL er offset 11               -10..HvisTur: A1-H8=11-88, HvidSort='H' | 'S' */
    FOR n IN 1..121 LOOP
      position(n) := ASCII('.');
    END LOOP;
    --
    InitializedStatic := TRUE;
    --WR('Initialize S2');
  ELSE
    NULL;
    --WR('Initialize S2 SKIP');
  END IF;
  PL_PIG_CHESS_ENGINE.STILL(position,STARTPOSITION);
  OUTPUT_POSITION;
  --IF PL_PIG_CHESS_ENGINE.EPD_BESTMOVE      IS NOT NULL THEN WR('EPD best move:       '||PL_PIG_CHESS_ENGINE.EPD_BESTMOVE);      END IF;
  --IF PL_PIG_CHESS_ENGINE.EPD_SECONDARYMOVE IS NOT NULL THEN WR('EPD secondary move:  '||PL_PIG_CHESS_ENGINE.EPD_SECONDARYMOVE); END IF;
  --IF PL_PIG_CHESS_ENGINE.EPD_AVOIDMOVE     IS NOT NULL THEN WR('EPD avoid move:      '||PL_PIG_CHESS_ENGINE.EPD_AVOIDMOVE);     END IF;
  --IF PL_PIG_CHESS_ENGINE.EPD_id            IS NOT NULL THEN WR('EPD id:              '||PL_PIG_CHESS_ENGINE.EPD_ID);            END IF;
  --IF PL_PIG_CHESS_ENGINE.EPD_COMMENT0      IS NOT NULL THEN WR('EPD primary comment: '||PL_PIG_CHESS_ENGINE.EPD_COMMENT0);      END IF;
  BlackToMove := position(PL_PIG_CHESS_ENGINE.stOff+ PL_PIG_CHESS_ENGINE_EVAL.Hvistur) = ASCII('S');
  IF NOT BlackToMove AND WhiteSide > 0 OR BlackToMove AND BlackSide > 0 THEN
    DO_BOTMOVE;
  END IF;
END NEW_GAME;

PROCEDURE DO_BOTMOVE(OverruleLevel SIMPLE_INTEGER DEFAULT 0) IS
  LV INTEGER;
BEGIN
    IF NOT InitializedStatic THEN
      NEW_GAME(2,0);
    END IF;
    IF BlackToMove THEN
      LV := FLOOR(BlackSide * 3 / 2) - 2;
    ELSE
      LV := FLOOR(WhiteSide * 3 / 2) - 2;
    END IF;
    IF LV < 1 OR OverruleLevel > 0 THEN
      LV := FLOOR(OverruleLevel * 3 / 2) - 2 ;
      IF LV < 1 THEN 
        LV :=1;
      END IF;
    END IF;
    --WR('lv='||LV||' WhiteSide='||WhiteSide||' BlackSide='||BlackSide);
    PL_PIG_CHESS_ENGINE.FindTrk(position, 
          Lv,--dybde SIMPLE_INTEGER, ---- depth: 0-9 (0,1,4,7,10,13) 
          0,-- ekstra SIMPLE_INTEGER, p.t. UNUSED
          Trk-- in out TRKDATA 
          );
    EvTot := EvTot + PL_PIG_CHESS_ENGINE_EVAL.Evals;
    --WR('træk='||MOVETXT(Trk,chr(position(PL_PIG_CHESS_ENGINE.stOff +Trk.Fra)))||' vlu='||Trk.vlu||' evals='||PL_PIG_CHESS_ENGINE_EVAL.Evals);      
    MOVETEXT := MOVETXT(Trk,chr(position(PL_PIG_CHESS_ENGINE.stOff+ Trk.Fra)));
    WR('lv='||LV||' move='||MOVETEXT||'  '||Trk.Fra ||Trk.Til||' vlu='||Trk.vlu||' typ='||Trk.Typ||' evals='||PL_PIG_CHESS_ENGINE_EVAL.Evals||' tot='||EvTot);      
    IF SET_IN(PL_PIG_CHESS_ENGINE.MOVEmat,Trk.Typ) OR SET_IN(PL_PIG_CHESS_ENGINE.MOVEpat,Trk.Typ) THEN
      WR('Game ended '||to_char(sysdate,'dd/mm-yyyy hh24:mi:ss'));
    ELSE
      IF PL_PIG_CHESS_ENGINE.DoMoveOK(position, Trk.Fra, Trk.Til, Trk.Typ) THEN
        BlackToMove := position(PL_PIG_CHESS_ENGINE.stOff+ PL_PIG_CHESS_ENGINE_EVAL.Hvistur)=ASCII('S');
      ELSE
        WR('Illegal move by engine ('||Trk.Fra||'-'||Trk.Til||')!');
      END IF;  
    END IF;
    --WR(POSITION_STR);
    OUTPUT_POSITION;
END DO_BOTMOVE;

PROCEDURE DO_BOTGAME(maxmoves SIMPLE_INTEGER DEFAULT 200) IS
 -- play a game bot vs bot
BEGIN
  FOR n in 1..maxmoves LOOP
    DO_BOTMOVE;
    IF SET_IN(PL_PIG_CHESS_ENGINE.MOVEmat,Trk.Typ) OR SET_IN(PL_PIG_CHESS_ENGINE.MOVEpat,Trk.Typ) THEN
      exit;
    END IF;
  END LOOP;
END DO_BOTGAME;  


PROCEDURE DO_MOVE(fromto VARCHAR2) IS -- move in the form 'e2e4' or 'g1f3' as black 'e7e5' or 'g8f6'
-- human move
  mvtyp PL_PIG_CHESS_ENGINE.MOVETYPE := 0;
  Ffrom varchar2(5);
  Fto   varchar2(5);
BEGIN
  IF NOT InitializedStatic THEN
    NEW_GAME(0,2);
  END IF;
  Ffrom :=substr(fromto,-4,2);
  Fto   :=substr(fromto,-2);
  IF Ffrom > '9' THEN
    Ffrom := substr(Ffrom,2)||CHR(ASCII(UPPER(substr(Ffrom,1,1)))-16);
  END IF;
  IF Fto > '9' THEN
    Fto := substr(Fto,2)||CHR(ASCII(UPPER(substr(Fto,1,1)))-16);
    WR(Ffrom||Fto);
  END IF;
  IF PL_PIG_CHESS_ENGINE.DoMoveOk(position,TO_NUMBER(Ffrom),TO_NUMBER(Fto), mvtyp) THEN
    OUTPUT_POSITION;
    BlackToMove := position(PL_PIG_CHESS_ENGINE.stOff+ PL_PIG_CHESS_ENGINE_EVAL.Hvistur)=ASCII('S');
    IF NOT BlackToMove AND WhiteSide > 0 OR BlackToMove AND BlackSide > 0 THEN
      DO_BOTMOVE;
    END IF;
  ELSE
    WR('Illegal move ('||fromto||')!');
  END IF;
END DO_MOVE;


PROCEDURE SET_White(White INTEGER  DEFAULT 0) IS -- alter engine/player-selection for White
BEGIN
  WhiteSide := White;
  IF WhiteSide > 0 AND NOT BlackToMove THEN
    DO_BOTMOVE; -- get engine move
  END IF;
END SET_White; 

PROCEDURE SET_Black(Black INTEGER  DEFAULT 0) IS -- alter engine/player-selection for Black
BEGIN
  BlackSide := Black;
  IF BlackSide > 0 AND BlackToMove THEN
    DO_BOTMOVE; -- get engine move
  END IF;
END SET_Black;

PROCEDURE TAKEBACK_MOVE IS--takes back the last move (if engine, it will move again, possibly the same move)
BEGIN--(not yet implemented!)
  NULL;
END TAKEBACK_MOVE;

PROCEDURE TAKEBACK_MOVES IS--takes back the last two moves (Player can retry another move)
BEGIN--(not yet implemented!)
  NULL;
END TAKEBACK_MOVES;

  
PROCEDURE test1 IS
  --st PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE := PL_PIG_CHESS_ENGINE_EVAL.STILLINGTYPE();
  --s VARCHAR2(80);
  --n INTEGER;m INTEGER;
  --c_n INTEGER; c CHAR(1);
  --
  pos1 VARCHAR2(89) :=
    'RSLDMLSR'
  ||'BBBBBBBB'
  ||'        '
  ||'        '
  ||'        '
  ||'        '
  ||'bbbbbbbb'
  ||'rsldmlsr'
  ||'H';
  --
  pos2 VARCHAR2(89) :=
    'R LDM SR'
  ||' BB LBB '
  ||'B SB   B'
  ||'    B   '
  ||'  l b   '
  ||'     s  '
  ||'bbbb bbb'
  ||'rsld rk '
  ||'H';
  --
  pos3 VARCHAR2(89) :=
    'RSLDMLSR'
  ||'BBBBBBBB'
  ||'        '
  ||'        '
  ||'        '
  ||'        '
  ||'bbbbbbbb'
  ||'rsldmlsr'
  ||'H';
  --
  pos4 VARCHAR2(89) :='R  DML RBBB  BBB  S BS   l B  l    b      s bd  bbb  bbbr   m  rS';
  res SIMPLE_INTEGER := 0;
  --trk PL_PIG_CHESS_ENGINE.TRKDATA;
  Lv INTEGER:=4;
BEGIN
  WR('START');--TOAD: Options -> Oracle -> General. About halfway down is a box titled "DBMS Output" Choose Courier font
  NEW_GAME(0, 0, pos4);
  OUTPUT_POSITION;
  --res := PL_PIG_CHESS_ENGINE_EVAL.Eval(position, 0, FALSE, -9999, 9999);
  --WR('Eval='||res);
  PL_PIG_CHESS_ENGINE.FindTrk(position, 
          Lv,--dybde SIMPLE_INTEGER, ---- dybde: 0-9 (0,1,4,7) 
          0,-- ekstra SIMPLE_INTEGER, p.t. UNUSED
          Trk-- in out TRKDATA 
          );
  EvTot := EvTot + PL_PIG_CHESS_ENGINE_EVAL.Evals;
  WR('træk='||MOVETXT(Trk,chr(position(PL_PIG_CHESS_ENGINE.stOff+ Trk.Fra)))||'  '||Trk.Fra ||Trk.Til||' vlu='||Trk.vlu||' typ='||Trk.Typ||' evals='||PL_PIG_CHESS_ENGINE_EVAL.Evals||' tot='||EvTot);      
  PL_PIG_CHESS_ENGINE.DoMove(position, Trk.Fra, Trk.Til, Trk.Typ);
  OUTPUT_POSITION;
  FOR n in 1..2 LOOP
    PL_PIG_CHESS_ENGINE.FindTrk(position, 
          Lv,--dybde SIMPLE_INTEGER, ---- dybde: 0-9 (0,1,4,7) 
          0,-- ekstra SIMPLE_INTEGER, p.t. UNUSED
          Trk-- in out TRKDATA 
          );
    EvTot := EvTot + PL_PIG_CHESS_ENGINE_EVAL.Evals;
    WR('træk='||MOVETXT(Trk,chr(position(PL_PIG_CHESS_ENGINE.stOff+ Trk.Fra)))||'  '||Trk.Fra ||Trk.Til||' vlu='||Trk.vlu||' typ='||Trk.Typ||' evals='||PL_PIG_CHESS_ENGINE_EVAL.Evals||' tot='||EvTot);      
    PL_PIG_CHESS_ENGINE.DoMove(position, Trk.Fra, Trk.Til, Trk.Typ);
    WR(POSITION_STR(FALSE));
  END LOOP;
  OUTPUT_POSITION;
  WR('FindCnt='||PL_PIG_CHESS_ENGINE.FindCnt||' QFindCnt='||PL_PIG_CHESS_ENGINE.QFindCnt);

END test1;

PROCEDURE test2 IS
  s VARCHAR2(80);
  --n INTEGER;m INTEGER;
  c_n INTEGER; c CHAR(1);
BEGIN
  WR('Preproc test');
  NEW_GAME(0);
  PL_PIG_CHESS_ENGINE_EVAL.PreProcessor(position);
  FOR c_n IN ASCII('B')..ASCII('t') LOOP
    c := chr(c_n);
    IF c IN ('B','b','l','L','K','k','S','s','T','t') THEN
      dbms_output.put_line('pdw for '||c);
      FOR yy in 1..8 LOOP  
        s:='. ';
        FOR xx in 1..8 LOOP 
            s := s||to_char(PL_PIG_CHESS_ENGINE_EVAL.pdw(PL_PIG_CHESS_ENGINE_EVAL.pdX(c,xx+10*(9-yy))),'099')||' ';  
        END LOOP; 
        WR(s);
      END LOOP;
    END IF;
  END LOOP;
END test2;

PROCEDURE WRMOVES IS
BEGIN
  WR('Engine='||SHORT(MOVETEXT)||' bm='||SHORT(PL_PIG_CHESS_ENGINE.EPD_BESTMOVE)
     ||CASE WHEN PL_PIG_CHESS_ENGINE.EPD_SECONDARYMOVE IS NOT NULL THEN ' sm='||SHORT(PL_PIG_CHESS_ENGINE.EPD_SECONDARYMOVE) END
     ||CASE WHEN PL_PIG_CHESS_ENGINE.EPD_AVOIDMOVE IS NOT NULL THEN ' am='||SHORT(PL_PIG_CHESS_ENGINE.EPD_AVOIDMOVE) END);
END WRMOVES;

PROCEDURE CLCPOINTS(p_points  in out INTEGER) IS      
-- calculate points by matching engine move vs test-suite best/worst move
 bm1 varchar2(80):=PL_PIG_CHESS_ENGINE.EPD_BESTMOVE;
 sm1 varchar2(80):=PL_PIG_CHESS_ENGINE.EPD_SECONDARYMOVE;
 am1 varchar2(80):=PL_PIG_CHESS_ENGINE.EPD_AVOIDMOVE;
 bm2 varchar2(80):='';
 sm2 varchar2(80):='';
 am2 varchar2(80):='';
 bm3 varchar2(80):='';
 bm4 varchar2(80):='';
 bmR varchar2(80):='';
 p INTEGER;
BEGIN
  p:=instr(bm1,' ');
  IF p > 1 THEN -- use first 4 moves only
    bm2 := substr(bm1,p+1);
    bm1 := substr(bm1,1,p-1);
    p:=instr(bm2,' ');
    IF p > 1 THEN 
      bm3 := substr(bm2,p+1);
      bm2 := substr(bm2,1,p-1);
      p:=instr(bm3,' ');
      IF p > 1 THEN 
        bm4 := substr(bm3,p+1);
        bm3 := substr(bm3,1,p-1);
        p:=instr(bm4,' ');
        IF p > 1 THEN 
          bmR := substr(bm4,p+1);
          bm4 := substr(bm4,1,p-1);
        END IF;  
      END IF;
    END IF;
  END IF;
  p:=instr(sm1,' ');
  IF p > 1 THEN -- use first 2 moves only
    sm2 := substr(sm1,p+1);
    sm1 := substr(sm1,1,p-1);
  END IF;
  p:=instr(am1,' ');
  IF p > 1 THEN -- use first 2 moves only
    am2 := substr(am1,p+1);
    am1 := substr(am1,1,p-1);
  END IF;
  IF SHORT(MOVETEXT)=SHORT(bm1) 
  OR SHORT(MOVETEXT)=SHORT(bm2) 
  OR SHORT(MOVETEXT)=SHORT(bm3) 
  OR SHORT(MOVETEXT)=SHORT(bm4) 
  OR SHORT(MOVETEXT)=SHORT(sm1) 
  OR SHORT(MOVETEXT)=SHORT(sm2) THEN 
    p_points := p_points + 1;
    WR('*** OK ***');
  ELSIF 
    SHORT(MOVETEXT) = SHORT(am1) OR SHORT(MOVETEXT) = SHORT(am2) THEN
    p_points := p_points - 1;
    WR('*** MISTAKE ***');
  END IF;
END CLCPOINTS;
    
PROCEDURE test_BKtest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 24) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
  bkRating INTEGER;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' The B-K test (henceforth BKT) Bratko-Kopec 24 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.bkTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  bkRating := 1100 + points*100  - CASE WHEN points < 1 THEN 100*(1-points) ELSE 0 END - CASE WHEN points > 9 THEN  50*(points-9) ELSE 0 END;
  WR(points||' points out of '||positions||' positions. BKT rating='||bkRating);
END;

PROCEDURE test_MSquickTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 24) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' The Quicktest by Michael Scheidl. 24 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.MSquickTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_THmyPosTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 16) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' MY POSITIONAL TEST SUITE by Tony Hedlund. 16 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.THmyPosTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_SLendgameTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 20) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' Endgame testsuite Sune Larsson 2006 / John Nunn. 20 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.SLendgameTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_CCRTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 25) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' One Hour Test by Larry Kaufman, published 1994 (Kaufman Test). 25 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.CCRTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_ColditzTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 30) IS
  positions  INTEGER:=0;
  points_old INTEGER;
  points INTEGER:=0;
  Score INTEGER:=0;
  cRating INTEGER;
BEGIN
  EvTot:=0;
  --https://www.schach-computer.info/wiki/index.php/Colditz_En
  WR('Level: '||lvl||' Colditz test suite by Ferdinand Mosca, CCC, December 30, 2016. 30 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.ColditzTest(tstpos),0,0);
    WRMOVES;
    points_old :=points;
    CLCPOINTS(points); 
    IF points > points_old THEN 
      IF TRANSLATE(PL_PIG_CHESS_ENGINE.EPD_COMMENT0,'0123456789#',
                                       '########## ') IN ('#','##','###') THEN
        Score := Score + TO_NUMBER(PL_PIG_CHESS_ENGINE.EPD_COMMENT0);
      END IF;  
    END IF;
  END LOOP;
  -- Calculate Colditz-rating (approximated):
  CASE WHEN Score <=1515 THEN
           cRating := 1700-round((1515-score)*0.55);
       WHEN  Score >=1788 THEN
           cRating := 2000+round((score-1788)*2,093);
       ELSE 
           cRating := 1700+round((score-1515)*1.1);
  END CASE;
  WR(points||' points out of '||positions||' positions. Colditz-score='||Score||' Colditz ELO rating='||cRating);
END;

PROCEDURE test_BBCTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 42) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' Big Book Of Combinations. 42 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.BBCTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;
 
PROCEDURE test_ReinfeldTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 300) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' Reinfeld''s (1945) 300 (tactical) positions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.ReinfeldTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_LCTIITest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 35) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' LCT II (Louguet Chess Test II by Frdric Louguet in 1994). 35 Testpositions (1-14=positional, 15-26=tactical, 27-35=endgame');
  --points= 30 if found on level 4, 20 on level 6, 10 on level 8
  --rating= 1900 + points
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.LCTIITest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_SBDTest(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 134) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' Silent but Deadly (sbd). 134 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.SBDTest(tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_STSTest(suite NUMBER, lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 100) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' Strategic Test Suite, (STS) 15 suites x 100 positions. Suite '||suite||':');
  WR(PL_PIG_CHESS_DATA.STSsuitesTest(suite));
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.STSTest((suite-1)*100+tstpos),0,0);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

PROCEDURE test_PIG(lvl NUMBER DEFAULT 2, poslow INTEGER DEFAULT 1 , poshigh INTEGER DEFAULT 4) IS
  positions  INTEGER:=0;
  points INTEGER:=0;
BEGIN
  EvTot:=0;
  WR('Level: '||lvl||' Pig-chess found errors. 4 Testpositions');
  FOR tstpos IN poslow..poshigh LOOP
    positions := positions + 1;
    NEW_GAME(lvl,lvl,PL_PIG_CHESS_DATA.PigTest(tstpos),0,1);
    WRMOVES;
    CLCPOINTS(points);        
  END LOOP;
  WR(points||' points out of '||positions||' positions.');
END;

END;
/


DROP PACKAGE BODY PL_PIG_CHESS_ENGINE_EVAL;

CREATE OR REPLACE PACKAGE BODY PL_PIG_CHESS_ENGINE_EVAL AS
--
--

-- LICENSE
--
-- PL_PIG_CHESS_ENGINE v 0.92,                  (c) Egon Von Bech Madsen, Denmark (ema@adm.ku.dk) 
--
-- This software is Diceware. Diceware is defined as Freware with one restriction:
--
--   For non-commercial use:
--      roll one dice until you get 6, then take a picture. That picture is your 10 year free license.
--
--   For commercial use of small or medium sized companies (Yearly revenue less than US$ 60 billion), like Oracle:
--      roll two dices until you get 6 6, then take a picture. That picture is your 10 year free license.
--
--   For commercial use of large sized companies (Yearly revenue more than US$ 60 billion), like Microsoft:
--      roll three dices until you get 6 6 6, then take a picture. That picture is your 10 year free license.
--
-- It is allowed to modify and share the code as long as this LICENSE-text is unmodified.
--
-- ****************************************************************************************
-- * Disclaimer (use at your own risk):                                               
-- * Any use of this software is strictly at your own risk, and I will not be liable for 
-- * any losses and damages in connection with the use of this software.
-- ****************************************************************************************
-- LICENSE <end>

-- PL_PIG_CHESS_ENGINE is a Chess Engine written in Oracle PL/SQL.
--
-- HISTORY
-- Migrated from the Engine of PIGbase4 v2.8, coded with M2Amiga Modula-2 v4.2 
--
-- The Engine is 3 packages:
-- PL_PIG_CHESS_ENGINE
-- PL_PIG_CHESS_ENGINE_EVAL
-- PL_PIG_CHESS_DATA
--
-- Also included is a package:
-- PL_PIG_CHESS_INTERFACE 
-- making it possible to play with the Engine and run some test-suites using DBMS_OUTPUT.

-- TECHNICAL (PL/SQL)
-- PL/SQL is a quite restricted and slow language, not the perfect choice for a Chess Engine.
-- If You want top strength, don't use PIG-Chess, but install a Stockfish Engine at Your HOST OS.
--
-- Fair Performance is reached by intensive use of VARRAYS, SIMPLE_INTEGER and INLINE'able SET operators. 
-- And by NOT using SQL features. The many initiations of arrays happens only one time pr session/game.
--
-- TECHNICAL (CHESS)
-- Opening book
-- Static evaluation
-- quiescence deepening minimax algorithm with alpha/beta cut-off and sort for better pruning
-- Q-search (deeper selective search on killer-moves like check)
-- Leaf evaluation
-- Single CPU only
-- Supports 5 levels (from few seconds to several minutes pr move).
-- Rating: up to 1600
-- FEN and EPD is supported.
--
-- INSTALLATION
-- Install the 4 packages on a Oracle database:
-- 1. PL_PIG_CHESS_DATA
-- 2. PL_PIG_CHESS_ENGINE_EVAL
-- 3. PL_PIG_CHESS_ENGINE
-- 4. PL_PIG_CHESS_INTERFACE
--
-- USE:
-- 1. Use SQL*PLUS or Toad/SQL-Developer with DBMS_OUTPUT activated
-- 2. Use examples seen in PL_PIG_CHESS_INTERFACE
--
-- OR:
-- Make your own graphical (APEX?) interface...


  ClosedE4 BOOLEAN;ClosedD4 BOOLEAN;ClosedE3 BOOLEAN;
  ClosedE5 BOOLEAN;ClosedD3 BOOLEAN;ClosedD5 BOOLEAN;
  LatePart BOOLEAN; --* LatePart of OpenGame or EndGame
  FirstW   BOOLEAN := FALSE; 

 /* PreProcess (static evaluation part 1, defaults): */
  RokeretBonus CONSTANT  SIMPLE_INTEGER  := 20; /* bonus for safe king */
  pd1080   CONSTANT  SIMPLE_INTEGER  := -9; /* edge */
  pd2070   CONSTANT  SIMPLE_INTEGER  := -2; /* near edge */
  pd3060   CONSTANT  SIMPLE_INTEGER  :=  3; /* large center */
  pd4050   CONSTANT  SIMPLE_INTEGER  :=  8; /* center*/
  pd1080qb CONSTANT  SIMPLE_INTEGER  :=  3; /* for queen and bishops */
  pd3060qb CONSTANT  SIMPLE_INTEGER  := -2; 
  pd3060qe CONSTANT  SIMPLE_INTEGER  :=  8; /* for queen in endgame */  
  pd1080k  CONSTANT  SIMPLE_INTEGER  :=  8; /* for king, edge*/
  pd2070k  CONSTANT  SIMPLE_INTEGER  := -5; /* for king, near edge*/
  pd3060k  CONSTANT  SIMPLE_INTEGER  :=-20; /* for king, large center */
  pd7R                  CONSTANT SIMPLE_INTEGER  := 20; /* rook on 7'th rank */ 
  pd8R                  CONSTANT SIMPLE_INTEGER  := 5;  /* rook on 8'th rank */ 
  pd6Q                  CONSTANT SIMPLE_INTEGER  :=  5;
  pd7Q                  CONSTANT SIMPLE_INTEGER  := 12; /* queen on 7'th rank */ 
  pd8Q                  CONSTANT SIMPLE_INTEGER  :=  5;
  pdkc12                CONSTANT SIMPLE_INTEGER  :=  9; /* penalty for king in centre */
  /*pdkc9                 CONSTANT SIMPLE_INTEGER  :=  7; */ /* penalty for king in centre */
  pdPcf                 CONSTANT SIMPLE_INTEGER  :=  9; /* Pawn center (c+f) bonus  */
  pdPde                 CONSTANT SIMPLE_INTEGER  := 17; /* Pawn center (d+e) bonus  */
  pdP                   CONSTANT SIMPLE_INTEGER  :=  8; /* pawn rank bonus :  6  7  8  9 start for below:   */
  pdPend                CONSTANT SIMPLE_INTEGER  := 11; /* pawn -"- endgame : 1, 3, 5, 7, 9, 11, 13, 15, 17 */
  PenalUndev            CONSTANT SIMPLE_INTEGER  := 12; /* Penalty for undelevoped pieces */

  /* PreProcessor (static evaluation part 2, adjustments according to position): */
  BishopPenalty         CONSTANT SIMPLE_INTEGER  :=  3; /* behind own pawns penalty */
  OpenGameValue         CONSTANT SIMPLE_INTEGER  :=  6; /* if FirstLineCount > 7*/
  EndGameValue          CONSTANT SIMPLE_INTEGER  := 10; /* if q*4+Q*4+r*2+R*2+n+N+b+B < */
  pdB5                  CONSTANT SIMPLE_INTEGER  :=  6; /* Bishop b5,g5 bonus/penalty */
  KingArea30            CONSTANT SIMPLE_INTEGER  := 30;
  KingArea20            CONSTANT SIMPLE_INTEGER  := 20;
  KingArea16            CONSTANT SIMPLE_INTEGER  := 16;
  KingArea12            CONSTANT SIMPLE_INTEGER  := 12;
  KingArea8             CONSTANT SIMPLE_INTEGER  :=  8;
  AroundKingBonus       CONSTANT SIMPLE_INTEGER  :=  5; /* by KingAdj: *1 *2 or *3 */
  PawnStrateg20         CONSTANT SIMPLE_INTEGER  := 15; /* strategical pawn moves when closed center */
  PawnStrateg10         CONSTANT SIMPLE_INTEGER  :=  8;
  BishopClosed          CONSTANT SIMPLE_INTEGER  := 15; /* penalty */
  BishopOpen            CONSTANT SIMPLE_INTEGER  :=  7;
  KnightClosed          CONSTANT SIMPLE_INTEGER  :=  7;
  RookFullOpenLine      CONSTANT SIMPLE_INTEGER  := 12;
  RookHalfOpenLine      CONSTANT SIMPLE_INTEGER  :=  8;
  EarlyKnight           CONSTANT SIMPLE_INTEGER  := 12; -- penalty 
  LateBishop            CONSTANT SIMPLE_INTEGER  :=  3; -- penalty 
  pawnh3a3attack        CONSTANT SIMPLE_INTEGER  :=  5;
  AvoidCastling         CONSTANT SIMPLE_INTEGER  :=  6; -- penalty 
  CastleBonus           CONSTANT SIMPLE_INTEGER  := 28;

-- Eval (dynamic evaluation):
  InMoveBonus                  CONSTANT SIMPLE_INTEGER := 10;
  --ActivityWeight               CONSTANT SIMPLE_INTEGER :=  0; --!!!!!!!!!!!!!!!!!!!!!! 1-5 (not used) !!!!!!*)
  TwoOnRow7                    CONSTANT SIMPLE_INTEGER :=350; --bonus for 2 advanced side by side pawns!
  TwoOnRow6                    CONSTANT SIMPLE_INTEGER :=150;
  TwoOnRow5                    CONSTANT SIMPLE_INTEGER := 50;
  RookFirstRowBehindPawn       CONSTANT SIMPLE_INTEGER :=  8; -- Penalty, 
  RookCornerNextToKing         CONSTANT SIMPLE_INTEGER := 30; -- Penalty, 
  RookCornerNextToPiece        CONSTANT SIMPLE_INTEGER :=  4; -- Penalty, 
  KingCloseRook                CONSTANT SIMPLE_INTEGER := 22; -- Penalty, (NOT endgame) king on c1 or f1 with rook behind 
  KingBehindPawns              CONSTANT SIMPLE_INTEGER := 12; --          (NOT endgame)
  QueenDeveloped               CONSTANT SIMPLE_INTEGER := 12; -- Penalty, (OpenGame)
  QueenBeforePawn              CONSTANT SIMPLE_INTEGER := 20; -- Penalty, (OpenGame)
  QueenBeforePawnBlockedBishop CONSTANT SIMPLE_INTEGER := 30; -- Penalty, (OpenGame)
  QueenBeforeBishop            CONSTANT SIMPLE_INTEGER := 15; -- Penalty, (OpenGame)
  BishopBeforePawn             CONSTANT SIMPLE_INTEGER := 13; -- Penalty, 
  BishopBehindPawn             CONSTANT SIMPLE_INTEGER :=  8; -- Penalty, 
  BishopProtectedByPawn        CONSTANT SIMPLE_INTEGER :=  8;
  kNightBeforePawn             CONSTANT SIMPLE_INTEGER := 10; -- Penalty, 
  kNightProtectedByPawn        CONSTANT SIMPLE_INTEGER :=  8;
  kNightpPawnInFront           CONSTANT SIMPLE_INTEGER := 12; -- blocks a opponent-pawn
  PawnNextToPawn               CONSTANT SIMPLE_INTEGER :=  8;
  PawnGuardsPawn               CONSTANT SIMPLE_INTEGER :=  5;
  PawnF3                       CONSTANT SIMPLE_INTEGER := 15; -- Penalty, (OpenGame)
  PawnDoubbledPawn             CONSTANT SIMPLE_INTEGER := 40; -- Penalty, (KingEndgame)
  knEndGamePrio                CONSTANT SIMPLE_INTEGER :=  6; --          (KingEndgame)
  knEndGameBprio               CONSTANT SIMPLE_INTEGER :=  6; --          (KingEndgame)
  SupportedPawnPenalty         CONSTANT SIMPLE_INTEGER := 50; -- penalty, (KingEndgame)
  SupportedPawn0911            CONSTANT SIMPLE_INTEGER := 50; --          (KingEndgame)
  SupportedPawn1020            CONSTANT SIMPLE_INTEGER := 20; --          (KingEndgame)
  SupportedPawn1921            CONSTANT SIMPLE_INTEGER := 80; --          (KingEndgame)
  BadDevelPenalty              CONSTANT SIMPLE_INTEGER := 17; -- penalty, (KingEndgame)
  BadDevelBishop               CONSTANT SIMPLE_INTEGER :=  6; -- penalty, (KingEndgame)
  BishopPairBonus              CONSTANT SIMPLE_INTEGER := 30; -- if half-open center, if full-open center then 2*
-- stuff:
  kOut     BOOLEAN;
  K_Out    BOOLEAN;
  stOff    CONSTANT SIMPLE_INTEGER  := 11; --offset for arrays Stilling
  p      SIMPLE_INTEGER:=0;
--
--FUNCTION pdX(brik SIMPLE_INTEGER, felt SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
--BEGIN -- two-dimensional array ('B'..'t', 11..88) -> 1..3979
--  RETURN (brik - 66) * 78 + felt - 10; -- ASCII('B')=66
--END pdX;
--
--
--compare with simple_integer is double speed than compare with char(1).
--Numeric representation of pieces to get best possible speed:

wN CONSTANT SIMPLE_INTEGER  := 115;--ASCII('s');--White kNight
bN CONSTANT SIMPLE_INTEGER  :=  83;--ASCII('S');--Black kNight
wB CONSTANT SIMPLE_INTEGER  := 108;--ASCII('l');--White Bishop
bB CONSTANT SIMPLE_INTEGER  :=  76;--ASCII('L');--Black Bishop
wR CONSTANT SIMPLE_INTEGER  := 116;--ASCII('t');--White Rook
bR CONSTANT SIMPLE_INTEGER  :=  84;--ASCII('T');--Black Rook
wC CONSTANT SIMPLE_INTEGER  := 114;--ASCII('r');--White rook with Castling
bC CONSTANT SIMPLE_INTEGER  :=  82;--ASCII('R');--Black rook with Castling
wQ CONSTANT SIMPLE_INTEGER  := 100;--ASCII('d');--White Queen
bQ CONSTANT SIMPLE_INTEGER  :=  68;--ASCII('D');--Black Queen
wP CONSTANT SIMPLE_INTEGER  :=  98;--ASCII('b');--White Pawn
bP CONSTANT SIMPLE_INTEGER  :=  66;--ASCII('B');--Black Pawn
wE CONSTANT SIMPLE_INTEGER  := 101;--ASCII('e');--White pawn En-passant
bE CONSTANT SIMPLE_INTEGER  :=  69;--ASCII('E');--Black pawn En-passant
wK CONSTANT SIMPLE_INTEGER  := 107;--ASCII('k');--White King
bK CONSTANT SIMPLE_INTEGER  :=  75;--ASCII('K');--Black King
wM CONSTANT SIMPLE_INTEGER  := 109;--ASCII('m');--White Majesty (king w castling)
bM CONSTANT SIMPLE_INTEGER  :=  77;--ASCII('M');--Black Majesty (king w castling)
wA CONSTANT SIMPLE_INTEGER  :=  97;--ASCII('a');--White pieces all bigger than this
bA CONSTANT SIMPLE_INTEGER  :=  65;--ASCII('A');--Pieces all bigger than this + reference index
wT CONSTANT SIMPLE_INTEGER  :=  72;--ASCII('H');--Whites Turn (index hvistur)
bT CONSTANT SIMPLE_INTEGER  :=  83;--ASCII('S');--Blacks Turn (index hvistur)
spc CONSTANT SIMPLE_INTEGER :=  32;--ASCII(' ');--Space
edge CONSTANT SIMPLE_INTEGER:=  46;--ASCII('.');--Edge-marker

FUNCTION UPPER_n(n SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
BEGIN
  IF n<wA THEN
    RETURN n;
  ELSE 
    RETURN n - 32;
  END IF;
END UPPER_n;
--
FUNCTION pdN(brik_n SIMPLE_INTEGER, felt SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
BEGIN -- two-dimensional array (bP..wR, 11..88) -> 1..3978. Here index is calculated out of Numeric repræsentation (ascii value) of pieces.
  --RETURN (brik - 66) * 78 + felt - 10; -- ASCII(bP)=66  ASCII(wR)=116
  RETURN brik_n * 78 -5158 + felt; -- ASCII(bP)=66
END pdN;

FUNCTION pdX(brik CHAR, felt SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
BEGIN -- two-dimensional array ('B'..'t', 11..88) -> 1..3978
  RETURN (ASCII(brik) - 66) * 78 + felt - 10; -- ASCII('B')=66
END pdX;

PROCEDURE WRT(s VARCHAR2) IS
BEGIN
  dbms_output.put_line(s);
END WRT;
--


PROCEDURE PreProcess IS
  n SIMPLE_INTEGER := 0;
  ix SIMPLE_INTEGER:= 0;
  m SIMPLE_INTEGER:= 0;
  t SIMPLE_INTEGER:= 0;
  v SIMPLE_INTEGER:= 0;
  f SIMPLE_INTEGER:= 0;
  --ch CHAR(1);
  ch_n SIMPLE_INTEGER:= 0; -- ASCII(CHAR);
BEGIN
  --pdw.extend(4000);
  p := 600;
  FOR ch_n IN bP..wR  LOOP  --clear all
    IF ch_n in (bP,bE,bR,bC,bN,bK,bM,bB,bQ, wP,wE,wR,wC,wN,wK,wM,wB,wQ) THEN
      ix := pdn(ch_n,0);
      FOR n in 1..8 LOOP  FOR m in 1..8 LOOP 
         pdw(ix + n*10+m) := 0;
         pdb(ix + n*10+m) := 0;
      END LOOP; END LOOP;
    END IF;
  END LOOP;
  --
  p := 601;
  FOR ch_n IN bP..bR  LOOP        /* positionel data, centrum bedst */
     p := 602;
     --ch := chr(ch_n);
     p := 604;
     CASE 
     WHEN ch_n in ( bP,bE,bR,bC,bN ) THEN
          p := 605;
          FOR n in 1..8 LOOP  FOR m in 1..8 LOOP 
            --p := 6052;
            --p := 6053;
            --WRT(chr(ch_n)||': '||to_char(n*10+m)||' '||pdN(ch_n,n*10+m));
            --p := 6054;
            --WRT(chr(ch_n)||n||m||' '||pdN(ch_,n*10+m));
            pdw(pdN(ch_n,n*10+m)):=pd1080;  
          END LOOP; END LOOP;
          p := 606;
          FOR n in 2..7 LOOP  FOR m in 2..7 LOOP pdw(pdN(ch_n,n*10+m)):=pd2070;  END LOOP; END LOOP;
          p := 607;
          IF ch_n in ( bP,bE,bN ) THEN -- Rooks not in center
            FOR n in 3..6 LOOP  FOR m in 3..6 LOOP pdw(pdN(ch_n,n*10+m)):=pd3060;  END LOOP; END LOOP;
            p := 610;
            FOR n in 4..5 LOOP  FOR m in 4..5 LOOP pdw(pdN(ch_n,n*10+m)):=pd4050;  END LOOP; END LOOP;
          END IF;
     WHEN ch_n in (bK,bM) THEN
          p := 620;
          IF Endgame THEN
            IF LatePart THEN
              FOR n in 1..8 LOOP  FOR m in 1..8 LOOP pdw(ix + n*10+m):=floor(-pd1080k/2);  END LOOP; END LOOP;
              FOR n in 2..7 LOOP  FOR m in 2..7 LOOP pdw(ix + n*10+m):=floor(-pd2070k/2);  END LOOP; END LOOP;
              FOR n in 3..6 LOOP  FOR m in 3..6 LOOP pdw(ix + n*10+m):=floor(-pd3060k/2);  END LOOP; END LOOP;
            END IF;
          ELSE
            FOR n in 1..8 LOOP  FOR m in 1..8 LOOP pdw(pdN(ch_n,n*10+m)):=pd1080k;  END LOOP; END LOOP;
            FOR n in 2..7 LOOP  FOR m in 2..7 LOOP pdw(pdN(ch_n,n*10+m)):=pd2070k;  END LOOP; END LOOP;
            FOR n in 3..6 LOOP  FOR m in 3..6 LOOP pdw(pdN(ch_n,n*10+m)):=pd3060k;  END LOOP; END LOOP;
          END IF;
      WHEN ch_n in (bB,bQ) THEN  /* løber,D ikke specielt i centrum, men fianciettering */
          p := 630;
          IF EndGame AND (ch_n=bQ) THEN t:=pd3060qe; ELSE t:=pd3060qb; END IF;
          FOR n in 1..8 LOOP  FOR m in 1..8 LOOP pdw(pdN(ch_n,n*10+m)):=pd1080qb;  END LOOP; END LOOP;
          FOR n in 3..6 LOOP  FOR m in 3..6 LOOP pdw(pdN(ch_n,n*10+m)):=t;  END LOOP; END LOOP;
      ELSE
          NULL;      
      END CASE;
  END LOOP;
  p := 639;
  IF OpenGame THEN
    p := 640;
    /* bonus to move pawns into the center */
    ix := pdN(bP,56); pdw(ix) := pdw(ix) + pdPcf;
    ix := pdN(bP,55); pdw(ix) := pdw(ix) + pdPde;
    ix := pdN(bP,54); pdw(ix) := pdw(ix) + pdPde;
    ix := pdN(bP,53); pdw(ix) := pdw(ix) + pdPcf;
    ix := pdN(bE,56); pdw(ix) := pdw(ix) + pdPcf;
    ix := pdN(bE,55); pdw(ix) := pdw(ix) + pdPde;
    ix := pdN(bE,54); pdw(ix) := pdw(ix) + pdPde;
    ix := pdN(bE,53); pdw(ix) := pdw(ix) + pdPcf;
    /* penalty to undeveloped pieces */
    ix := pdN(bN,82); pdw(ix) := pdw(ix) - PenalUndev;
    ix := pdN(bB,83); pdw(ix) := pdw(ix) - PenalUndev;
    ix := pdN(bQ,84); pdw(ix) := pdw(ix) - PenalUndev;
    ix := pdN(bB,86); pdw(ix) := pdw(ix) - PenalUndev;
    ix := pdN(bN,87); pdw(ix) := pdw(ix) - PenalUndev;
    ix := pdN(bP,74); pdw(ix) := pdw(ix) - PenalUndev;
    ix := pdN(bP,75); pdw(ix) := pdw(ix) - PenalUndev;
  ELSE
    p := 650;
  /* tårne (rook) + Dronning (queen) på (at) 7+8 række (row) bonus */
    FOR n IN 1..8 LOOP
      pdw(pdN(bR,20+n)):=pd7R;   
      pdw(pdN(bR,10+n)):=pd8R;
      pdw(pdN(bQ,30+n)):=pd6Q;
      pdw(pdN(bQ,20+n)):=pd7Q;
      pdw(pdN(bQ,10+n)):=pd8Q;
    END LOOP;
    p := 660;

    /* bønder (pawns) mere værd jo tættere de er på forvandling (promotion) 7, 9 */
    IF EndGame THEN t := pdPend; ELSE t := pdP; END IF;
    FOR n IN 2..7 LOOP
      v := (t-n)*(t-n);
      FOR m IN 1..8 LOOP
           f :=10*n+m;
           ix := pdN(bP,f); pdw(ix) := pdw(ix) + v;
           ix := pdN(bE,f); pdw(ix) := pdw(ix) + v;
       END LOOP;
    END LOOP;
  END IF;
  p := 670;

  /* Knights worth a bit less */
  IF EndGame THEN
    FOR n IN 1..8 LOOP
      FOR m IN 1..8 LOOP
        ix := pdN(bN,10*n+m); pdw(ix) := pdw(ix) -12;
      END LOOP;
    END LOOP;
  END IF;
  
  /* spejl af sort til hvid*/
  FOR ch_n IN wP..wR LOOP 
     --ch := chr(ch_n);
    CASE WHEN ch_n IN (wP,wE,wR,wC,wK,wM,wQ,wN,wB ) THEN
        FOR n in 1..8 LOOP
          FOR m in 1..8 LOOP
              pdw(pdN(ch_n,n+10*m)) :=pdw(pdN(UPPER_n(ch_n),99-n-10*m));
          END LOOP;
        END LOOP;
    ELSE
      NULL;
    END CASE;
  END LOOP;

  p := 680;


  /* konge (king) mere værd hvis i sikkerhed (secure) */
  IF not EndGame THEN
    p := 690;
    FOR m IN 1..2 LOOP
      FOR n IN 2..3 LOOP
         ix := pdN(wK,m*10+5-n);    pdw(ix) := RokeretBonus;-- castlingbonus
         ix := pdN(wK,m*10+5+n);    pdw(ix) := RokeretBonus;
         ix := pdN(bK,90-m*10+5-n); pdw(ix) := RokeretBonus;
         ix := pdN(bK,90-m*10+5+n); pdw(ix) := RokeretBonus;
      END LOOP;
      FOR n IN 4..6 LOOP
         ix := pdN(wK,m*10+n);      pdw(ix) := pdw(ix) - pdkc12;
         ix := pdN(bK,90-m*10+n);   pdw(ix) := pdw(ix) -pdkc12;
      END LOOP;
    END LOOP;
    /* 5-98: develop king-side bishops */
     ix := pdN(wB,16);      pdw(ix) := pdw(ix) - 3;
     ix := pdN(wB,86);      pdw(ix) := pdw(ix) - 3;
  END IF;
  p := 699;

  /*pd:=pdw;*/
  EXCEPTION
    WHEN OTHERS THEN
      dbms_output.put_line('Preprocess p='||p||': '||sqlerrm);
  END PreProcess;
  
  PROCEDURE PreProcessor(stilling STILLINGTYPE) IS
/* adjusts the pd-array+OpenGame+EngGame according..the actual position. */
/* Is called one time for each engine call */
    dd SIMPLE_INTEGER := 0; -- PL/SQL is not case sensitive
    tt SIMPLE_INTEGER := 0;
    ll SIMPLE_INTEGER := 0; 
    ss SIMPLE_INTEGER := 0;
    bbb SIMPLE_INTEGER := 0;
    defenders SIMPLE_INTEGER := 0;
    D SIMPLE_INTEGER := 0;
    T SIMPLE_INTEGER := 0;
    L SIMPLE_INTEGER := 0;
    S SIMPLE_INTEGER := 0;
    B SIMPLE_INTEGER := 0; 
    n SIMPLE_INTEGER := 0;
    m SIMPLE_INTEGER := 0;
    n_n SIMPLE_INTEGER := 0;-- BY 10 helper
    m_n SIMPLE_INTEGER := 0;-- BY 10 helper
    f SIMPLE_INTEGER := 0;
    FirstLineCount SIMPLE_INTEGER := 0; 
    wkk SIMPLE_INTEGER := 0;
    bkk SIMPLE_INTEGER := 0;
    kx SIMPLE_INTEGER := 0;
    ky SIMPLE_INTEGER := 0;
   
    x SIMPLE_INTEGER := 0;
    y SIMPLE_INTEGER := 0;
    y_n SIMPLE_INTEGER := 0;-- BY 10 helper
    v SIMPLE_INTEGER := 0;
    nm SIMPLE_INTEGER := 0;
    om SIMPLE_INTEGER := 0;
    sw SIMPLE_INTEGER := 0;
    ch_n SIMPLE_INTEGER := 0;
    nbb SIMPLE_INTEGER := 0;
    nB SIMPLE_INTEGER := 0;
    TYPE Rtyp is VARRAY(8)OF BOOLEAN;
    R  Rtyp := Rtyp(FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE); -- stores TRUE if line open for (Black) rooks
    rr Rtyp := Rtyp(FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE);
    NoWoffs BOOLEAN;--None White Officers
    NoBoffs BOOLEAN;
    ix SIMPLE_INTEGER:= 0;
PROCEDURE KingAdj(k SIMPLE_INTEGER) IS
  WpieceCnt SIMPLE_INTEGER := 0;
  BpieceCnt SIMPLE_INTEGER := 0;
  fc CHAR(1);
BEGIN p := 100;
  x:=MOD(k,10);
  y:=FLOOR(k/10);
  WpieceCnt:=0;
  BpieceCnt:=0;
  FOR n IN x-2..x+2 LOOP
    FOR m IN y-2..y+2 LOOP
      IF (n>0) AND (n<9) AND (m>0) AND (m<9) THEN 
        f:=n+10*m;
        IF stilling(stOff+ f)>spc THEN
          IF stilling(stOff+ f) = UPPER_n(stilling(stOff+ f)) THEN BpieceCnt:=BpieceCnt+1; ELSE WpieceCnt:= WpieceCnt+1; END IF;
        END IF;
      END IF;
    END LOOP;
  END LOOP;
  IF stilling(stOff+ k)=UPPER_n(stilling(stOff+ k)) THEN -- black king, then swap
    n:=BpieceCnt;
    BpieceCnt:=WpieceCnt;
    WpieceCnt:=n;
  END IF;
  IF WpieceCnt+BpieceCnt<10 THEN
    WpieceCnt := WpieceCnt+3;
  ELSIF WpieceCnt+BpieceCnt<13 THEN
    WpieceCnt := WpieceCnt+2;
  ELSIF WpieceCnt+BpieceCnt<17 THEN
    WpieceCnt := WpieceCnt+1;
  END IF;
  IF WpieceCnt-BpieceCnt>7 THEN
    ll:=0;
  ELSIF WpieceCnt-BpieceCnt>5 THEN
    ll:=AroundKingBonus;
  ELSIF WpieceCnt-BpieceCnt>4 THEN
    ll:=AroundKingBonus*2;
  ELSE
    ll:=AroundKingBonus*3;
  END IF;
  FOR n IN x-2..x+2 LOOP
    FOR m  IN y-2..y+2 LOOP
      IF (n>0) AND (n<9) AND (m>0) AND (m<9) THEN 
        f:=n+10*m;
        --WRT('KingAdj: '||f||' + '||ll);
        ix := pdN(bQ,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(bR,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(bB,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(bN,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(bP,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(wQ,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(wR,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(wB,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(wN,f); Pdw(ix) := Pdw(ix) + ll;
        ix := pdN(wP,f); Pdw(ix) := Pdw(ix) + ll;--rettet 'n' -> wP
      END IF;
    END LOOP;
  END LOOP;
   p := 199;
END KingAdj;--in PreProcessor
PROCEDURE PieceAdjust IS
BEGIN p := 200;
  IF PieceClear THEN
    FOR x IN 1..8 LOOP
      FOR y IN 1..8 LOOP
        v:=x+10*y;
        pdw(pdN(wK,v)):=0; --pdw(pdN(wK,v] DIV 2;
        pdw(pdN(bK,v)):=0; --pdw(pdN(bK,v] DIV 2;
      END LOOP;
    END LOOP;
  END IF;
  FOR x IN 1..8 LOOP
    FOR y IN 1..8 LOOP
      v:=x+10*y;
      IF stilling(stOff+ v)>spc THEN
        FOR n IN x-4..x+4 LOOP
          FOR m IN y-4..y+4 LOOP
            IF (n>0) AND (n<9) AND (m>0) AND (m<9) AND ((n<>x) OR (m<>y)) THEN 
              f:=n+10*m;
              ll:=FLOOR((26-ABS(y-m)*ABS(x-n)) /  2); -- 12,11,8,5
              IF stilling(stOff+ v)<>wK THEN ix := pdN(wK,f); Pdw(ix) := Pdw(ix) + ll; END IF; 
              IF stilling(stOff+ v)<>bK THEN ix := pdN(bK,f); Pdw(ix) := Pdw(ix) + ll; END IF; 
            END IF;
          END LOOP;
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;
  IF PieceDecr THEN
    FOR x IN 1..8 LOOP 
      FOR y IN 1..8 LOOP 
        ix := pdN(wK,x+10*y); Pdw(ix) := Pdw(ix) - 50; --DEC(pdw(pdN(wK,x+10*y],50); 
        ix := pdN(bK,x+10*y); Pdw(ix) := Pdw(ix) - 50; --DEC(pdw(pdN(bK,x+10*y],50); 
      END LOOP; 
    END LOOP;
  END IF;
  p := 299;
END PieceAdjust;--in PreProcessor
PROCEDURE SetP(brik SIMPLE_INTEGER, distance SIMPLE_INTEGER, valuee SIMPLE_INTEGER) IS
  kx SIMPLE_INTEGER := 0;
  ky SIMPLE_INTEGER := 0;
  x SIMPLE_INTEGER := 0;
  y SIMPLE_INTEGER := 0;
BEGIN  p := 300;                 -- brik=white piece (adjusts for black too)
  kx:=MOD(bkk,  10);
  ky:=FLOOR(bkk / 10);
  FOR x IN kx-distance..kx+distance LOOP
    FOR y IN ky-distance..ky+distance LOOP
      IF (x>0) AND (x<9) AND (y>0) AND (y<9)
      AND ((ABS(x-kx)=distance) OR (ABS(y-ky)=distance)) THEN
        ix := pdN(brik,x+10*y); Pdw(ix) := Pdw(ix) + valuee;
      END IF;
    END LOOP;
  END LOOP;
  kx:=MOD (wkk, 10);
  ky:=FLOOR(wkk / 10);
  FOR x IN kx-distance..kx+distance LOOP
    FOR y IN ky-distance..ky+distance LOOP
      IF (x>0) AND (x<9) AND (y>0) AND (y<9)
      AND ((ABS(x-kx)=distance) OR (ABS(y-ky)=distance)) THEN
        ix := pdN(UPPER_n(brik),x+10*y); Pdw(ix) := Pdw(ix) + valuee;
      END IF;
    END LOOP;
  END LOOP;
  p := 399;
END SetP;-- in PreProcessor
BEGIN  p := 400;--PreProcessor
  --WRT('PREPROCESSOR');
  IF not FirstW THEN --one-time initialization (allocation+initial-values) of varray variables.
    Initialize;
  END IF;
--(*$ IF Test0 WRITELNF(s('PreProcessor...')); --(*$ ENDIF

  -- init variables
  dd:=0; tt:=0; ll:=0; ss:=0; bbb:=0; D:=0; T:=0; L:=0; S:=0; B:=0;
  ClosedE4:=FALSE; ClosedD4:=FALSE; ClosedE3:=FALSE;
  ClosedE5:=FALSE; ClosedD5:=FALSE; ClosedD3:=FALSE;

  FirstLineCount:=16; -- 16 pieces minus empty fields

  -- count pieces
  FOR n IN 11..88 LOOP
    CASE stilling(stOff+ n) 
    WHEN  wQ THEN  dd := dd + 1; -- white queen
    WHEN  bQ THEN  D  := D + 1;  -- black queen
    WHEN  wR THEN  tt := tt + 1; -- white rook
    WHEN  wC THEN  tt := tt + 1; -- white rook, castleable
    WHEN  bR THEN  T  := T + 1;  -- black rook
    WHEN  bC THEN  T  := T + 1;  -- black rook, castleable
    WHEN  wB THEN  ll := ll + 1; -- white bishop
    WHEN  bB THEN  L  := L +1;   -- black bishop
    WHEN  wN THEN  ss := ss + 1; -- white knight
    WHEN  bN THEN  S  := S + 1;  -- black knight
    WHEN  wP THEN  bbb:= bbb + 1; -- white pawn
    WHEN  wE THEN  bbb:= bbb + 1; -- white pawn, enpassantable 
    WHEN  bP THEN  B  := B + 1;  -- black pawn
    WHEN  bE THEN  B  := B + 1;  -- black pawn, enpassantable 
    WHEN  wK THEN  kOut  := n=15;-- white king 
    WHEN  wM THEN  kOut  := n=15;-- white king, castleable 
    WHEN  bK THEN  K_Out := n=85;-- black king 
    WHEN  bM THEN  K_Out := n=85;-- black king, castleable
    ELSE
      IF (n<19) OR (n>80) THEN FirstLineCount := FirstLineCount - 1; END IF;
    END CASE;
  END LOOP;
  NoBoffs :=  (S=0) AND (L=0) AND (D=0) AND (T=0);    --none black officers
  NoWoffs := (ss=0) AND (ll=0) AND (dd=0) AND (tt=0); --none white officers
  p := 410;
  -- set global flags (5 combinations):
  --  1. opengame, NOT latepart
  --  2. opengame, latepart
  --  3. NOT opengame, NOT endgame, latepart
  --  4. endgame, NOT latepart
  --  5. endgame, latepart
  OpenGame :=FirstLineCount>OpenGameValue;
  IF OpenGame THEN
    LatePart:=FirstLineCount<OpenGameValue+3;
    EndGame :=FALSE;
  ELSE
    EndGame  :=dd*3+D*3+tt*2+T*2+ss+S+ll+L < EndGameValue;
    IF EndGame THEN
      LatePart:=dd*3+D*3+tt*2+T*2+ss+S+ll+L < EndGameValue-4;
    END IF;
  END IF;

  IF EndGame and PieceClearEarly  THEN
    FOR x IN 1..8 LOOP
      FOR y IN 1..8 LOOP
        v:=x+10*y;
        pdw(pdN(wK,v)):=0; --pdw(pdN(wK,v] DIV 2;
        pdw(pdN(bK,v)):=0; --pdw(pdN(bK,v] DIV 2;
      END LOOP;
    END LOOP;
  END IF;
  
  -- set default positional values (in pd)
  PreProcess;
 
  -- White king positions calc
  IF stilling(stOff+ 15)=wM THEN 
    wkk:=15;
    IF NOT EndGame THEN
      ix := pdN(wK,17); pdw(ix) := pdw(ix) + CastleBonus+9;
      ix := pdN(wK,13); pdw(ix) := pdw(ix) + CastleBonus-9;
    END IF;
  ELSE
    wkk:=11;
    WHILE (stilling(stOff+ wkk)<>wK) AND (wkk<88) LOOP 
      wkk := wkk + 1; 
    END LOOP;
  END IF;
  --WRT('wkk='||wkk);
  
  
  -- Black king positions calc  
  IF stilling(stOff+ 85)=bM THEN
    p := 1441;
    bkk:=85;
    IF NOT EndGame THEN
      p := 1442;
      ix := pdN(bK,87); pdw(ix) := pdw(ix) + CastleBonus+9;
      ix := pdN(bK,83); pdw(ix) := pdw(ix) + CastleBonus-9;
    END IF;
  ELSE
    bkk:=88;
    p := 1444;
    WHILE (stilling(stOff+ bkk)<>bK) AND (bkk>11) LOOP 
      bkk := bkk -1; 
    END LOOP;
    p := 1448;
  END IF;
  --WRT('bkk='||bkk);
  
 
  -- Mating, 4-Double value of pawns to try to promote or Added value to
  -- get lonely king to the edge
  IF NoBoffs AND (B=0) THEN
    FOR x IN 1..8 LOOP
      FOR y IN 1..8 LOOP
        n:=x+10*y;
        IF bbb=0 THEN
          IF Follow THEN
            ix := pdn(bK,n);
            IF (y=1) OR (y=8) THEN -- on Y edge
               pdw(ix) := pdw(ix) -100;--WRT('B100');
            END IF;
            IF (x=1) OR (x=8) THEN -- on X edge
               pdw(ix) := pdw(ix) -100;--WRT('B100');
            END IF;
            IF (y=2) OR (y=7) THEN -- next to Y edge
               pdw(ix) := pdw(ix) -50;--WRT('B50');
            END IF;
            IF (x=2) OR (x=7) THEN -- next to X edge
               pdw(ix) := pdw(ix) -50;--WRT('B50');
            END IF;
            IF (y=3) OR (y=6)   THEN -- not in Y center
               pdw(ix) := pdw(ix) -25;--WRT('B25');
            END IF;
            IF (x=3) OR (x=6)  THEN -- not in X center
               pdw(ix) := pdw(ix) -25;--WRT('B25');
            END IF;
          ELSE
            IF (n<19) OR (n>70) OR (x=1) OR (x=8) THEN
              ix := pdX('K',n); pdw(ix) := pdw(ix) -60;
            ELSIF (n<29) OR (n>60) OR (x=2) OR (x=7) THEN
              ix := pdX('K',n); pdw(ix) := pdw(ix) -30;
            END IF;
          END IF;
        ELSE
          ix := pdN(wP,n); pdw(ix) := pdw(ix)*4;--WRT('B*4');
        END IF;
      END LOOP;
    END LOOP;
    IF Follow THEN
      kx:=MOD(bkk,  10);-- bonus for moving king towards the king to mate
      ky:=FLOOR(bkk / 10);    
      FOR x IN kx-2..kx+2 LOOP
        IF x>0 and x<9 THEN
          FOR y IN ky-2..ky+2 LOOP
            IF y>0 and y<9 THEN
              IF (y between ky-2 and ky+2) and (x between kx-2 and kx+2) THEN
                ix := pdn(wK,x+10*y);
                IF (y = ky-2 or y = ky+2) and (x = kx-2 or x = kx+2) THEN
                  pdw(ix) := pdw(ix) + 15;                 
                ELSE
                  pdw(ix) := pdw(ix) + 30;
                END IF;
--                WRT('bonus for moving king towards the black king to mate yx='||y||x);
              END IF;
            END IF;
          END LOOP;
        END IF;
      END LOOP;     
    END IF; 
    --
  END IF;
--
--  IF NoBoffs AND (B>0) AND (bbb>0) THEN
--    FOR x IN 1..8 LOOP
--      FOR y IN 1..8 LOOP
--        n:=x+10*y;
--        ix := pdN(wP,n); pdw(ix) := pdw(ix)*4;
--      END LOOP;
--    END LOOP;
--  END IF;

  IF NoWoffs AND (bbb=0) THEN
    FOR x in 1..8 LOOP
      FOR y in 1..8 LOOP
        n:=x+10*y;
        IF B=0 THEN
          IF Follow THEN
            ix := pdn(wK,n);
            IF (y=1) OR (y=8) THEN -- on Y edge
               pdw(ix) := pdw(ix) -100;--WRT('W100');
            END IF;
            IF (x=1) OR (x=8) THEN -- on X edge
               pdw(ix) := pdw(ix) -100;--WRT('W100');
            END IF;
            IF (y=2) OR (y=7) THEN -- next to Y edge
               pdw(ix) := pdw(ix) -50;--WRT('W50');
            END IF;
            IF (x=2) OR (x=7) THEN -- next to X edge
               pdw(ix) := pdw(ix) -50;--WRT('W50');
            END IF;
            IF (y=3) OR (y=6)   THEN -- not in Y center
               pdw(ix) := pdw(ix) -25;--WRT('W25');
            END IF;
            IF (x=3) OR (x=6)  THEN -- not in X center
               pdw(ix) := pdw(ix) -25;--WRT('W25');
            END IF;
          ELSE
            IF (n<19) OR (n>70) OR (x=1) OR (x=8) THEN
              ix := pdX('k',n); pdw(ix) := pdw(ix) -60;
            ELSIF (n<29) OR (n>60) OR (x=2) OR (x=7) THEN
              ix := pdX('k',n); pdw(ix) := pdw(ix) -30;
            END IF;
          END IF;
        ELSE
          ix := pdN(bP,n); pdw(ix) := pdw(ix)*4;--WRT('W*4');
        END IF;
      END LOOP;
    END LOOP;
    --
    IF Follow THEN
      kx:=MOD(wkk,  10);-- bonus for moving king towards the king to mate
      ky:=FLOOR(wkk / 10);    
      FOR x IN kx-2..kx+2 LOOP
        IF x>0 and x<9 THEN
          FOR y IN ky-2..ky+2 LOOP
            IF y>0 and y<9 THEN
              IF (y between ky-2 and ky+2) and (x between kx-2 and kx+2) THEN
                ix := pdn(bK,x+10*y);
                IF (y = ky-2 or y = ky+2) and (x = kx-2 or x = kx+2) THEN
                  pdw(ix) := pdw(ix) + 15;                 
                ELSE
                  pdw(ix) := pdw(ix) + 30;
                END IF;
--                WRT('bonus for moving king towards the white king to mate yx='||y||x);
              END IF;
            END IF;
          END LOOP;
        END IF;
      END LOOP;   
    END IF;   
    --
  END IF;
  p := 420;
  --
 -- IF NoWoffs AND (bbb>0) AND (B>0) THEN
 --   FOR x IN 1..8 LOOP
 --     FOR y IN 1..8 LOOP
 --       n:=x+10*y;
 --       ix := pdN(bP,n); pdw(ix) := pdw(ix)*4;
 --     END LOOP;
 --   END LOOP;
 -- END IF;

  -- calc pawn center type
  IF (stilling(stOff+ 44)=wP) AND (stilling(stOff+ 54)=bP) THEN--rettet 54=wP til 54=bP
    ClosedD4:=TRUE;
    IF (stilling(stOff+ 35)=wP) AND (stilling(stOff+ 45)=bP) THEN ClosedE3 :=TRUE; END IF;
    IF (stilling(stOff+ 55)=wP) AND (stilling(stOff+ 65)=bP) THEN ClosedE5 :=TRUE; END IF;
  ELSIF (stilling(stOff+ 45)=wP) AND (stilling(stOff+ 55)=bP) THEN--rettet 55=wP til 55=bP
    ClosedE4:=TRUE;
    IF (stilling(stOff+ 34)=wP) AND (stilling(stOff+ 44)=bP) THEN ClosedD3 :=TRUE; END IF;
    IF (stilling(stOff+ 54)=wP) AND (stilling(stOff+ 64)=bP) THEN ClosedD5 :=TRUE; END IF;
  END IF;
  
  p := 424;
  IF (stilling(stOff+ HvisTur)=bT) THEN -- 5-98
    IF NOT NoBoffs AND NoWoffs THEN --pawn endgame
      FOR x IN 1..8 LOOP
        FOR y IN 1..8 LOOP
          n:=x+10*y;
          pdw(pdN(bP,n)):=pdw(pdN(bP,n))*2;-- rettet fra pdb til pdw
        END LOOP;
      END LOOP;
    END IF;
  ELSE
    IF NOT NoWoffs AND NoBoffs THEN
       FOR x IN 1..8 LOOP
        FOR y IN 1..8 LOOP
          n:=x+10*y;
          pdw(pdN(wP,n)):=pdw(pdN(wP,n))*2;
        END LOOP;
      END LOOP;
    END IF;
  END IF;
  p := 426;

  -- rook open lines calc
  FOR x IN 1..8 LOOP
    rr(x):=TRUE;
    R(x):=TRUE;
    FOR y_n IN 2..7 LOOP
      y := y_n*10;
      IF (stilling(stOff+ y+x)=wP) OR (stilling(stOff+ y+x)=wE) THEN rr(x):=FALSE; END IF;
      IF (stilling(stOff+ y+x)=bP) OR (stilling(stOff+ y+x)=bE) THEN R(x):=FALSE; END IF;
    END LOOP;
  END LOOP;
 p := 430;

  IF NOT EndGame AND NOT (OpenGame AND NOT LatePart) AND KingAir THEN--!!!!!!!!!new may19: air for king in mid-game:
    IF wkk = 17 and stilling(stOff+ 26)=wP and stilling(stOff+ 27)=wP and stilling(stOff+ 28)=wP  THEN
      defenders :=0;
      FOR sc IN 11..16 LOOP
         IF stilling(stOff+ sc) in (wR,wQ) THEN defenders := defenders + 1; END IF;
      END LOOP;
      IF stilling(stOff+ 16) in (wB,wN)  THEN defenders := defenders + 1; END IF;   
      IF defenders < 2 THEN ix := pdN(wP,27); pdw(ix) := pdw(ix) + defendersWeight*4 - defenders*defendersWeight*2; pdw(ix+1) := pdw(ix+1) + defendersWeight*6 - defenders*defendersWeight*3; END IF;
    ELSIF wkk = 12 and stilling(stOff+ 21)=wP and stilling(stOff+ 22)=wP and stilling(stOff+ 23)=wP THEN
      defenders :=0;
      FOR sc IN 13..18 LOOP
         IF stilling(stOff+ sc) in (wR,wQ) THEN defenders := defenders + 1; END IF;
      END LOOP;
      IF stilling(stOff+ 13) in (wB,wN)  THEN defenders := defenders + 1; END IF;   
      IF defenders < 2 THEN ix := pdN(wP,22); pdw(ix) := pdw(ix) + defendersWeight*4 - defenders*defendersWeight*2; pdw(ix-1) := pdw(ix-1) + defendersWeight*6 - defenders*defendersWeight*3; END IF;    
    END IF;
  END IF;
  --

  IF NOT EndGame AND (wkk=15) OR OpenGame AND (( MOD(wkk,10)>3) OR ( MOD(wkk,10)<7)) THEN
    -- king castling eval (avoid a side?)
    f:=0; -- O-O-O
    IF (stilling(stOff+ 21)<>wP) AND (stilling(stOff+ 31)<>wP) THEN f := f + 1; END IF;
    IF (stilling(stOff+ 22)<>wP) AND (stilling(stOff+ 22)<>wB) AND (stilling(stOff+ 33)<>wB) THEN f := f + 1; END IF;
    IF stilling(stOff+ 23)<>wP THEN f := f + 1; END IF;
    FOR x IN 1..3 LOOP 
      IF R(x) THEN f := f + 1; END IF; 
    END LOOP;
    IF f>0 THEN 
      ix := pdN(wK,13); pdw(ix) := pdw(ix) - f*f*AvoidCastling;
    END IF;
    f:=0; -- O-O
    IF (stilling(stOff+ 28)<>wP) AND (stilling(stOff+ 38)<>wP) THEN f := f + 1; END IF;
    IF (stilling(stOff+ 27)<>wP) AND (stilling(stOff+ 27)<>wB)  AND (stilling(stOff+ 36)<>wB) THEN f := f + 1; END IF;
    IF stilling(stOff+ 26)<>wP THEN f := f + 1; END IF;
    FOR x IN 6..8 LOOP IF rr(x) THEN f := f +1; END IF; END LOOP;
    IF f>0 THEN
      ix := pdN(wK,17); pdw(ix) := pdw(ix) - f*f*AvoidCastling;
    ELSE
      IF (stilling(stOff+ 15)=wM) AND (stilling(stOff+ 16)=wB) AND (stilling(stOff+ 17)=wN) THEN
        -- undeveloped king-side penalty
        ix := pdN(wB,16); pdw(ix) := pdw(ix) - 8;
        ix := pdN(wN,17); pdw(ix) := pdw(ix) - 8;
      END IF; 
    END IF;
  END IF;
  --p := 439;
  --dbms_output.put_line(length(stilling(stOff+ 85)));
  
  p := 440;
    IF NOT EndGame AND NOT (OpenGame AND NOT LatePart) AND KingAir THEN-----------------new may19: air for king in mid-game:
    IF bkk = 87 and stilling(stOff+ 76)=bP and stilling(stOff+ 77)=bP and stilling(stOff+ 78)=bP  THEN
      defenders :=0;
      FOR sc IN 81..86 LOOP
         IF stilling(stOff+ sc) in (bR,bQ) THEN defenders := defenders + 1; END IF;
      END LOOP;
      IF stilling(stOff+ 86) in (bB,bN)  THEN defenders := defenders + 1; END IF;   
      IF defenders < 2 THEN ix := pdN(bP,77); pdw(ix) := pdw(ix) + defendersWeight*4 - defenders*defendersWeight*2; pdw(ix+1) := pdw(ix+1) + defendersWeight*6 - defenders*defendersWeight*3; END IF;
    ELSIF bkk = 82 and stilling(stOff+ 71)=bP and stilling(stOff+ 72)=bP and stilling(stOff+ 73)=bP THEN
      defenders :=0;
      FOR sc IN 83..88 LOOP
         IF stilling(stOff+ sc) in (bR,bQ) THEN defenders := defenders + 1; END IF;
      END LOOP;
      IF stilling(stOff+ 83) in (bB,bN)  THEN defenders := defenders + 1; END IF;   
      IF defenders < 2 THEN ix := pdN(bP,72); pdw(ix) := pdw(ix) + defendersWeight*4 - defenders*defendersWeight*2; pdw(ix-1) := pdw(ix-1) + defendersWeight*6 - defenders*defendersWeight*3; END IF;    
    END IF;
  END IF;
  --

  p := 442;
  IF NOT EndGame AND (bkk=85) OR OpenGame AND ((MOD(bkk,10)>3) OR (MOD(bkk,10)<7)) THEN
    p := 443;
    f:=0; -- O-O-O
    IF (stilling(stOff+ 71)<>bP) AND (stilling(stOff+ 61)<>bP) THEN f := f + 1; END IF;
    IF (stilling(stOff+ 72)<>bP) AND (stilling(stOff+ 72)<>bB) AND (stilling(stOff+ 63)<>bB) THEN f := f + 1; END IF;
    IF stilling(stOff+ 73)<>bP THEN f := f + 1; END IF;
    FOR x IN 1..3 LOOP IF rr(x) THEN f := f + 1; END IF; END LOOP;
    IF f>0 THEN 
      ix := pdN(bK,83); pdw(ix) := pdw(ix) - f*f*AvoidCastling;
    END IF;
    f:=0; -- O-O
    IF (stilling(stOff+ 78)<>bP) AND (stilling(stOff+ 68)<>bP) THEN f := f +1; END IF;
    IF (stilling(stOff+ 77)<>bP) AND (stilling(stOff+ 77)<>bB) AND (stilling(stOff+ 66)<>bB) THEN f := f +1; END IF;
    IF stilling(stOff+ 76)<>bP THEN  f := f +1; END IF;
    p := 446;
    FOR x IN 6..8 LOOP IF rr(x) THEN  f := f + 1; END IF; END LOOP;
    p := 447;
    IF f>0 THEN
      p := 448;
      ix := pdN(bK,87); pdw(ix) := pdw(ix) - f*f*AvoidCastling;
    ELSE
      IF (stilling(stOff+ 85)=bM) AND (stilling(stOff+ 86)=bB) AND (stilling(stOff+ 87)=bN) THEN -- undeveloped king-side penalty
        p := 449;
        ix := pdN(bB,86); pdw(ix) := pdw(ix) - 8;
        ix := pdN(bN,87); pdw(ix) := pdw(ix) - 8;
      END IF; 
    END IF;
  END IF;
 p := 450;
 
  -- adjust around opponent king (wk,bk) as better fields (mating)
  IF EndGame THEN
    -- attract the kings to areas with pieces, own AND opponents
    p := 452;
    PieceAdjust;
    p := 453;    
    SetP(wQ,0,KingArea30);
    p := 454;
    SetP(wQ,1,KingArea30);
    SetP(wQ,2,KingArea20);
    SetP(wQ,3,KingArea12);
    SetP(wQ,4,KingArea8);
    SetP(wR,0,KingArea30);
    SetP(wR,1,KingArea30);
    SetP(wR,2,KingArea20);
    SetP(wR,3,KingArea12);
    SetP(wR,4,KingArea8);
    SetP(wK,0,KingArea20);
    SetP(wK,1,KingArea20);
    SetP(wK,2,KingArea16);
    SetP(wK,3,KingArea12);
    SetP(wK,4,KingArea8);
  ELSE
    p := 460;
    IF (stilling(stOff+ 11)=wR) AND (wkk=12) OR (wkk=13) THEN -- rook in corner
      ix := pdN(wR,11); pdw(ix) := pdw(ix) - 10;
      ix := pdN(wR,21); pdw(ix) := pdw(ix) - 10;
      ix := pdN(wR,12); pdw(ix) := pdw(ix) - 10;
      ix := pdN(wK,14); pdw(ix) := pdw(ix) - FLOOR(RokeretBonus / 2) ;
      ix := pdN(wK,21); pdw(ix) := pdw(ix) + RokeretBonus+10;
      ix := pdN(wK,22); pdw(ix) := pdw(ix) + RokeretBonus+10;
      ix := pdN(wK,23); pdw(ix) := pdw(ix) + RokeretBonus;
      IF (stilling(stOff+ wkk+9)=wP) AND (stilling(stOff+ wkk+10)=wP) THEN
        ix := pdN(wP,31); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(wP,32); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(wP,33); pdw(ix) := pdw(ix) + RokeretBonus;
        ix := pdN(wP,41); pdw(ix) := pdw(ix) + RokeretBonus+10;
      END IF;
    END IF;
    IF (stilling(stOff+ 18)=wR) AND (wkk=17) OR (wkk=16) THEN -- rook in corner
      ix := pdN(wR,18); pdw(ix) := pdw(ix) - 10;
      ix := pdN(wR,28); pdw(ix) := pdw(ix) - 10;
      ix := pdN(wR,17); pdw(ix) := pdw(ix) - 10;
      ix := pdN(wK,15); pdw(ix) := pdw(ix) - FLOOR(RokeretBonus/2);
      ix := pdN(wK,28); pdw(ix) := pdw(ix) + RokeretBonus+10;
      ix := pdN(wK,27); pdw(ix) := pdw(ix) + RokeretBonus+10;
      ix := pdN(wK,26); pdw(ix) := pdw(ix) + RokeretBonus;
      IF (stilling(stOff+ wkk+11)=wP) AND (stilling(stOff+ wkk+10)=wP) THEN
        ix := pdN(wP,38); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(wP,37); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(wP,36); pdw(ix) := pdw(ix) + RokeretBonus;
        ix := pdN(wP,48); pdw(ix) := pdw(ix) + RokeretBonus+10;
      END IF;
    END IF;

    IF (stilling(stOff+ 81)=bR) AND (bkk=82) OR (bkk=83) THEN -- rook in corner
      ix := pdN(bR,81); pdw(ix) := pdw(ix) - 10;
      ix := pdN(bR,71); pdw(ix) := pdw(ix) - 10;
      ix := pdN(bR,82); pdw(ix) := pdw(ix) - 10;
      ix := pdN(bK,84); pdw(ix) := pdw(ix) - FLOOR(RokeretBonus/2);
      ix := pdN(bK,71); pdw(ix) := pdw(ix) + RokeretBonus+10;
      ix := pdN(bK,72); pdw(ix) := pdw(ix) + RokeretBonus+10;
      ix := pdN(bK,73); pdw(ix) := pdw(ix) + RokeretBonus;
      IF (stilling(stOff+ bkk-11)=bP) AND (stilling(stOff+ bkk-10)=bP) THEN
        ix := pdN(bP,61); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(bP,62); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(bP,63); pdw(ix) := pdw(ix) + RokeretBonus;
        ix := pdN(bP,51); pdw(ix) := pdw(ix) + RokeretBonus+10;
      END IF;
    END IF;
    
    IF (stilling(stOff+ 88)=bR) AND (bkk=87) OR (bkk=86) THEN -- rook in corner
      ix := pdN(bR,88); pdw(ix) := pdw(ix) - 10;
      ix := pdN(bR,78); pdw(ix) := pdw(ix) - 10;
      ix := pdN(bR,87); pdw(ix) := pdw(ix) - 10;
      ix := pdN(bK,85); pdw(ix) := pdw(ix) - FLOOR(RokeretBonus/2);
      ix := pdN(bK,78); pdw(ix) := pdw(ix) + RokeretBonus+16;
      ix := pdN(bK,77); pdw(ix) := pdw(ix) + RokeretBonus+16;
      ix := pdN(bK,76); pdw(ix) := pdw(ix) + RokeretBonus;
      IF (stilling(stOff+ bkk-9)=bP) AND (stilling(stOff+ bkk-10)=bP) THEN
        ix := pdN(bP,68); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(bP,67); pdw(ix) := pdw(ix) + RokeretBonus+10;
        ix := pdN(bP,66); pdw(ix) := pdw(ix) + RokeretBonus;
        ix := pdN(bP,58); pdw(ix) := pdw(ix) + RokeretBonus+10;
      END IF;
    END IF;

    -- king positions adjust up around
    p := 470;
    KingAdj(wkk);
    KingAdj(bkk);
  END IF;

  -- if closed center, add value to strategical pawn moves, decrement bad bishop
  IF ClosedD4 THEN
    IF ClosedE5 THEN
      ix := pdN(wP,46); pdw(ix) := pdw(ix) + PawnStrateg10;
      ix := pdN(wP,56); pdw(ix) := pdw(ix) + PawnStrateg20;
      ix := pdN(bP,53); pdw(ix) := pdw(ix) + PawnStrateg20;
    END IF;
    IF ClosedE3 THEN
      ix := pdN(wP,43); pdw(ix) := pdw(ix) + PawnStrateg20;
      ix := pdN(bP,56); pdw(ix) := pdw(ix) + PawnStrateg10;
      ix := pdN(bP,46); pdw(ix) := pdw(ix) + PawnStrateg20;
    END IF;   
    IF ClosedE5 OR ClosedE3 THEN -- decrement white/black bad bishops on own half
      FOR m IN 1..4 LOOP
        FOR n IN 1..4 LOOP
          f:=10*m+n*2;
          IF MOD(m,2)=1 THEN
            ix := pdN(wB,f-1);  pdw(ix) := pdw(ix) - BishopClosed ;
            ix := pdN(bB,f+40); pdw(ix) := pdw(ix) - BishopClosed ;
          ELSE
            ix := pdN(wB,f);    pdw(ix) := pdw(ix) - BishopClosed ;
            ix := pdN(bB,f+39); pdw(ix) := pdw(ix) - BishopClosed ;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END IF;
  p := 472;
  IF ClosedE4 THEN
    IF ClosedD5 THEN
      ix := pdN(wP,43); pdw(ix) := pdw(ix) + PawnStrateg10;
      ix := pdN(wP,53); pdw(ix) := pdw(ix) + PawnStrateg20;
      ix := pdN(bP,56); pdw(ix) := pdw(ix) + PawnStrateg20;
    END IF;
    IF ClosedD3 THEN
      ix := pdN(wP,46); pdw(ix) := pdw(ix) + PawnStrateg20;
      ix := pdN(bP,53); pdw(ix) := pdw(ix) + PawnStrateg10;
      ix := pdN(bP,43); pdw(ix) := pdw(ix) + PawnStrateg20;
    END IF;   
    IF ClosedD5 OR ClosedD3 THEN -- decrement white/black bad bishops on own half
      FOR m IN 1..4 LOOP
        FOR n IN 1..4 LOOP
          f:=10*m+n*2;
          IF MOD(m,2)=1 THEN
            ix := pdN(wB,f);    pdw(ix) := pdw(ix) - BishopClosed;
            ix := pdN(bB,f+39); pdw(ix) := pdw(ix) - BishopClosed;
          ELSE
            ix := pdN(wB,f-1);    pdw(ix) := pdw(ix) - BishopClosed;
            ix := pdN(bB,f+40);   pdw(ix) := pdw(ix) - BishopClosed;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END IF;

  -- add value to bishops if open center
  IF NOT ClosedD4 AND NOT ClosedE4 THEN
    FOR n IN 11..88 LOOP
      ix := pdN(wB,n); pdw(ix) := pdw(ix) + BishopOpen;
      ix := pdN(bB,n); pdw(ix) := pdw(ix) + BishopOpen;
    END LOOP;
  END IF;

  -- add value to knights if closed center
  IF ClosedD4 AND (ClosedE3 OR ClosedE5) OR  ClosedE4 AND (ClosedD3 OR ClosedD5) THEN
    FOR n IN 11..88 LOOP
      ix := pdN(wN,n); pdw(ix) := pdw(ix) + KnightClosed;
      ix := pdN(bN,n); pdw(ix) := pdw(ix) + KnightClosed;
    END LOOP;
  END IF;

  -- rooks bonus on open lines
  FOR n IN 1..8 LOOP
    nbb:=0; nB:=0;
    FOR m IN 2..7 LOOP
      ch_n:=stilling(stOff+ 10*m+n);
      IF ch_n=wP THEN nbb := nbb+1; END IF;
      IF ch_n=bP THEN nbb := nbb+1; END IF;
    END LOOP;
    IF nbb=0 THEN
      IF nB=1 THEN f:=RookHalfOpenLine; ELSE f:=RookFullOpenLine; END IF;
      FOR m in 1..2 LOOP
        ix := pdN(wR,10*m+n); pdw(ix) := pdw(ix) + f;
      END LOOP;
      IF ((n=1) OR (n=8)) THEN 
        ix := pdN(wC,10+n); pdw(ix) := pdw(ix) + f;
      END IF;
    END IF;
    IF nB=0 THEN
      IF nbb=1 THEN f:=RookHalfOpenLine; ELSE f:=RookFullOpenLine; END IF;
      FOR m in 7..8 LOOP
        ix := pdN(bR,10*m+n); pdw(ix) := pdw(ix) + f;
      END LOOP;
      IF ((n=1) OR (n=8)) THEN 
        ix := pdN(bC,10+n); pdw(ix) := pdw(ix) + f;
      END IF;
    END IF;
  END LOOP;
  
  p := 480;
  IF OpenGame THEN
    p := 481;
    -- Bishop b/g5 bonus if not too early
    IF (stilling(stOff+ 33)=wN) THEN 
      ix := pdN(bB,42); pdw(ix) := pdw(ix) + pdB5;
    ELSE 
      ix := pdN(bB,42); pdw(ix) := pdw(ix) - FLOOR(pdB5/2);
    END IF;
    IF (stilling(stOff+ 63)=bN) THEN 
      ix := pdN(wB,52); pdw(ix) := pdw(ix) + pdB5;
    ELSE 
      ix := pdN(wB,52); pdw(ix) := pdw(ix) - FLOOR(pdB5/2);
    END IF;
    IF (stilling(stOff+ 36)=wN) THEN 
      ix := pdN(bB,47); pdw(ix) := pdw(ix) + pdB5;
    ELSE 
      ix := pdN(bB,47); pdw(ix) := pdw(ix) - FLOOR(pdB5/2);
    END IF;
    IF (stilling(stOff+ 66)=bN) THEN 
      ix := pdN(wB,57); pdw(ix) := pdw(ix) + pdB5;
    ELSE 
      ix := pdN(wB,57); pdw(ix) := pdw(ix) - FLOOR(pdB5/2);
    END IF;
    
    -- too early knights
    IF (stilling(stOff+ 44)=wP) AND (stilling(stOff+ 54)=spc) THEN
      IF stilling(stOff+ 63)=bN THEN
        ix := pdN(bP,54); pdw(ix) := pdw(ix) + EarlyKnight;
        ix := pdN(bP,65); pdw(ix) := pdw(ix) + EarlyKnight;
      ELSE
        ix := pdN(bN,63); pdw(ix) := pdw(ix) - EarlyKnight;
        IF stilling(stOff+ 75)=bP THEN 
          ix := pdN(bN,63); pdw(ix) := pdw(ix) - EarlyKnight;
        END IF;
      END IF;
    END IF;
    IF (stilling(stOff+ 54)=bP) AND (stilling(stOff+ 44)=spc) THEN 
      IF stilling(stOff+ 33)=wN THEN
        ix := pdN(wP,44); pdw(ix) := pdw(ix) + EarlyKnight;
        ix := pdN(wP,35); pdw(ix) := pdw(ix) + EarlyKnight;
      ELSE
        ix := pdN(wN,33); pdw(ix) := pdw(ix) - EarlyKnight;
        IF stilling(stOff+ 25)=wP THEN 
          ix := pdN(wN,33); pdw(ix) := pdw(ix) - EarlyKnight;
        END IF;
      END IF;
    END IF;
    IF (stilling(stOff+ 45)=wP) AND (stilling(stOff+ 55)=spc) THEN 
      IF stilling(stOff+ 66)=bN THEN
        ix := pdN(bP,55); pdw(ix) := pdw(ix) + EarlyKnight;
        ix := pdN(bP,64); pdw(ix) := pdw(ix) + EarlyKnight;
      ELSE
        ix := pdN(bN,66); pdw(ix) := pdw(ix) - EarlyKnight;
        IF stilling(stOff+ 74)=bP THEN 
          ix := pdN(bN,66); pdw(ix) := pdw(ix) - EarlyKnight;
        END IF;
      END IF;
    END IF;
    IF (stilling(stOff+ 55)=bP) AND (stilling(stOff+ 45)=spc) THEN 
      IF stilling(stOff+ 36)=wN THEN
        ix := pdN(wP,45); pdw(ix) := pdw(ix) + EarlyKnight;
        ix := pdN(wP,34); pdw(ix) := pdw(ix) + EarlyKnight;
      ELSE
        ix := pdN(wN,36); pdw(ix) := pdw(ix) - EarlyKnight;
        IF stilling(stOff+ 24)=wP THEN 
          ix := pdN(wN,36); pdw(ix) := pdw(ix) - EarlyKnight;
        END IF;
      END IF;
    END IF;
  END IF;
  
  -- too early bishops
  IF (stilling(stOff+ 33)=spc) AND (stilling(stOff+ 23)=wP) THEN
    ix := pdN(bB,42); pdw(ix) := pdw(ix) - EarlyKnight;
  END IF;
  IF (stilling(stOff+ 36)=spc) AND (stilling(stOff+ 26)=wP) THEN
    ix := pdN(bB,47); pdw(ix) := pdw(ix) - EarlyKnight;
  END IF;
  IF (stilling(stOff+ 63)=spc) AND (stilling(stOff+ 73)=bP) THEN
    ix := pdN(wB,52); pdw(ix) := pdw(ix) - EarlyKnight;
  END IF;
  IF (stilling(stOff+ 66)=spc) AND (stilling(stOff+ 76)=bP) THEN
    ix := pdN(wB,57); pdw(ix) := pdw(ix) - EarlyKnight;
  END IF;
  IF NOT EndGame THEN
    -- too late bishops
    ix := pdN(bB,86); pdw(ix) := pdw(ix) - LateBishop;
    ix := pdN(bB,83); pdw(ix) := pdw(ix) - LateBishop;
    ix := pdN(wB,13); pdw(ix) := pdw(ix) - LateBishop;
    ix := pdN(wB,16); pdw(ix) := pdw(ix) - LateBishop;
  END IF;

  -- h3
  IF (stilling(stOff+ 47)=bB) OR (stilling(stOff+ 47)=bN) THEN 
    ix := pdN(wP,38); pdw(ix) := pdw(ix) + pawnh3a3attack;
  END IF;
  IF (stilling(stOff+ 57)=wB) OR (stilling(stOff+ 57)=wN) THEN 
    ix := pdN(bP,68); pdw(ix) := pdw(ix) + pawnh3a3attack;
  END IF;
  IF (stilling(stOff+ 42)=bB) OR (stilling(stOff+ 42)=bN) THEN 
    ix := pdN(wP,31); pdw(ix) := pdw(ix) + pawnh3a3attack;--før 38, må være en fejl
  END IF;
  IF (stilling(stOff+ 52)=wB) OR (stilling(stOff+ 52)=wN) THEN 
    ix := pdN(bP,61); pdw(ix) := pdw(ix) + pawnh3a3attack;--før 68, må være en fejl
  END IF;
  
  p := 490;
  --  penalty for bishops behind own pawns
  FOR n_n IN 1..5 LOOP -- LOOP it for whites first 5 rows
    n := n_n*10;
    FOR m IN 1..8 LOOP
      IF stilling(stOff+ n+m)=wP THEN
        IF stilling(stOff+ n+10+m)=bP THEN v:=BishopPenalty*2; ELSE v:=BishopPenalty; END IF; 
        FOR f IN 1..m-1 LOOP -- to left edge
          IF 10*f<n THEN -- if on-board 
            ix := pdN(wB,n-10*f+f); pdw(ix) := pdw(ix) - v;
          END IF;
        END LOOP;
        FOR f IN 1..8-m LOOP -- to right edge
          IF 10*f<n THEN
            ix := pdN(wB,n-10*f+m+f); pdw(ix) := pdw(ix) - v;
          END IF;
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;
  FOR n_n IN 4..8 LOOP -- LOOP it for blacks first 5 rows
    n := n_n * 10;
    FOR m IN 1..8 LOOP
      IF stilling(stOff+ n+m)=bP THEN 
        IF stilling(stOff+ n-10+m)=wP THEN v:=BishopPenalty*2; ELSE v:=BishopPenalty; END IF;
        FOR f IN 1..m-1 LOOP -- to left edge
          IF 10*f+n<90 THEN -- if on-board
            ix := pdN(bB,n+10*f+f); pdw(ix) := pdw(ix) - v;
          END IF;
        END LOOP;
        FOR f IN 1..8-m LOOP -- to right edge
          IF 10*f+n<90 THEN
            ix := pdN(bB,n+10*f+m+f); pdw(ix) := pdw(ix) - v;
          END IF;
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;
  p := 492;
      
  -- mirror pdw to pdb
  FOR ch_n IN wP..wR LOOP 
    CASE 
      WHEN CH_n in ( wP,wE,wR,wC,wK,wM,wQ,wN,wB) THEN
      FOR n IN 1..4 LOOP 
        nm:=10*n;
        om:=90-nm;
        FOR m IN 1..8 LOOP
          nm:=nm+1;
          om:=om+1;
          pdb(pdN(ch_n,nm))        := pdw(pdN(UPPER_n(ch_n),om));
          pdb(pdN(ch_n,om))        := pdw(pdN(UPPER_n(ch_n),nm));
          pdb(pdN(UPPER_n(ch_n),nm)) := pdw(pdN(ch_n,om));
          pdb(pdN(UPPER_n(ch_n),om)) := pdw(pdN(ch_n,nm));
        END LOOP;
      END LOOP;
    ELSE 
      NULL;
    END CASE;
  END LOOP;
  p := 499;
  --dbms_output.put_line(p);
EXCEPTION
  WHEN OTHERS THEN
    dbms_output.put_line('PreProcessor p='||p||': '||sqlerrm);
    --raise;
END PreProcessor;


FUNCTION Eval(stilling STILLINGTYPE, Activity SIMPLE_INTEGER,
              Black BOOLEAN, alpha SIMPLE_INTEGER, beta SIMPLE_INTEGER) RETURN SIMPLE_INTEGER IS
/* evaluates the actual postion using pd and position. */
/* Is called thousands of times for each engine call! */


  n     SIMPLE_INTEGER := 0;
  m     SIMPLE_INTEGER := 0;
  res   SIMPLE_INTEGER := 0;
  kposs SIMPLE_INTEGER := 0;
  Kpos  SIMPLE_INTEGER := 0;
  x     SIMPLE_INTEGER := 0;
  y     SIMPLE_INTEGER := 0;
  y_n   SIMPLE_INTEGER := 0;
  inmv SIMPLE_INTEGER  := 0;   -- Positionel, matriel værdi
  brik           SIMPLE_INTEGER := 0;
  ch             SIMPLE_INTEGER := 0; -- ny
  KingEndGameW  BOOLEAN;
  KingEndGameB  BOOLEAN; -- if k or k+n endgame W/B
  knEndGameW    BOOLEAN;
  knEndGameB    BOOLEAN; -- if k+n endgame W/B      
  priW          SIMPLE_INTEGER := 0;
  priB          SIMPLE_INTEGER := 0; -- for k or kn endgame     
  TYPE pawnsType is varray(89) of BOOLEAN;
  Wpawns  pawnsType := pawnsType(); -- uses 11..89, but is 1..89
  Bpawns  pawnsType := pawnsType();
  pawnsInit BOOLEAN:=FALSE;
  TYPE pawnLineType is varray(8) of SIMPLE_INTEGER;
  WpL   pawnLineType := pawnLineType(); -- var SHORTINT
  BpL   pawnLineType := pawnLineType(); -- Pawns on line (iopb) 
  WpLc          SIMPLE_INTEGER := 0;
  BpLc          SIMPLE_INTEGER := 0; -- Pawns Total (if only pawns back) 
  HvidsTur      BOOLEAN;
  Slut          BOOLEAN;
  wBishops      SIMPLE_INTEGER := 0;
  bBishops      SIMPLE_INTEGER := 0;
  DebugS VARCHAR2(89);
  OpenCenterDegree SIMPLE_INTEGER :=2;
BEGIN
  HvidsTur := stilling(stOff+ HvisTur)<>bN;
  IF HvidsTur THEN 
    inmv:=InMoveBonus;
  ELSE
    inmv:=-InMoveBonus;
  END IF;
  Evals := Evals+1;
  posi  := 0;
  wbonus:= 0;
  bbonus:= 0;
  matr  := 0;
  -- based on static eval, how open is center pawn-structure
  IF  ClosedE4 AND (ClosedD3 or ClosedD5) OR  ClosedD4 AND (ClosedE3 or ClosedE5) THEN 
    OpenCenterDegree:= 0;
  ELSIF ClosedE4 and not ClosedD4 or ClosedD4 and not ClosedE4 THEN
    OpenCenterDegree:= 1;
  --ELSE   
  --  OpenCenterDegree:= 2;--default
  END IF;
  -- KingEndgame if just pawns and knights left. knEndGame if knights left.
  KingEndGameW:=TRUE; knEndGameW:=FALSE;
  KingEndGameB:=TRUE; knEndGameB:=FALSE;
  FOR n IN 11..88 LOOP
    brik:=stilling(stOff+ n);
    IF (brik>bA) THEN 
--WRT(brik);
      CASE WHEN brik IN
        (wR,wC) THEN 
                    matr:=matr+ValueT; KingEndGameW:=FALSE;
                    IF (n<50) THEN
                      IF (stilling(stOff+ n+10)=wP) OR (stilling(stOff+ n+20)=wP) THEN
                        wbonus:=wbonus-RookFirstRowBehindPawn;
                      END IF;
                    END IF;
                    IF n=11 THEN
                      IF brik=wC THEN matr:=matr+(ValueR-ValueT); END IF;
                      IF stilling(stOff+ 12)<>spc THEN
                        IF stilling(stOff+ 12)=wK THEN
                          wbonus:=wbonus-RookCornerNextToKing;
                        ELSE
                          wbonus:=wbonus-RookCornerNextToPiece;
                        END IF;
                      END IF;
                    ELSIF n=18 THEN
                      IF brik=wC THEN matr:=matr+(ValueR-ValueT); END IF;
                      IF stilling(stOff+ 17)<>spc THEN
                        IF stilling(stOff+ 17)=wK THEN
                          wbonus:=wbonus-RookCornerNextToKing;
                        ELSE
                          wbonus:=wbonus-RookCornerNextToPiece;
                        END IF;
                      END IF;
                    END IF;
        WHEN brik=wM  THEN 
                    matr:=matr+ValueM; kposs:=n;
        WHEN brik= wK     THEN 
                    matr:=matr+ValueK; kposs:=n;
                    IF NOT EndGame THEN
                      IF (n=16) AND ((stilling(stOff+ 18)=wR) OR (stilling(stOff+ 17)=wR))
                      OR (n=13) AND ((stilling(stOff+ 11)=wR) OR (stilling(stOff+ 12)=wR)) THEN
                        IF (n=16) AND (stilling(stOff+ 26)=wP) AND (stilling(stOff+ 27)=wP) 
                        OR (n=13) AND (stilling(stOff+ 23)=wP) AND (stilling(stOff+ 22)=wP) THEN
                          wbonus:=wbonus-KingCloseRook;
                        END IF;
                      ELSE
                        FOR m IN n+9..n+11 LOOP
                          IF stilling(stOff+ m)=wP THEN wbonus:=wbonus+12; END IF;
                        END LOOP;
                        wbonus:=wbonus-KingBehindPawns;
                      END IF;
                    END IF;
        WHEN brik= wQ     THEN matr:=matr+ValueD; KingEndGameW:=FALSE;
                    IF OpenGame THEN
                      IF n>28 THEN
                        wbonus:=wbonus-QueenDeveloped;
                        IF n>41 THEN
                          wbonus:=wbonus-12;
                        ELSE
                          IF (n=34) AND (stilling(stOff+ 24)=wP) THEN
                            wbonus:=wbonus-QueenBeforePawn;
                            IF (stilling(stOff+ 13)=wB) AND (stilling(stOff+ 22)=wP) THEN
                              wbonus:=wbonus-QueenBeforePawnBlockedBishop;
                            END IF;
                          ELSIF (n=35) AND (stilling(stOff+ 25)=wP) THEN
                            wbonus:=wbonus-QueenBeforePawn;
                            IF (stilling(stOff+ 16)=wB) AND (stilling(stOff+ 27)=wP) THEN
                              wbonus:=wbonus-QueenBeforePawnBlockedBishop;
                            END IF;
                          END IF;
                        END IF;
                      ELSIF (n=24) AND (stilling(stOff+ 13)=wB) AND (stilling(stOff+ 22)=wP)
                      OR    (n=25) AND (stilling(stOff+ 16)=wB) AND (stilling(stOff+ 27)=wP) THEN
                        wbonus :=wbonus-QueenBeforeBishop;
                      END IF;
                    END IF;
        WHEN brik= wB     THEN 
                    matr:=matr+ValueL; KingEndGameW:=FALSE;wBishops:=wBishops+1;
                    IF (n<39) AND (n>30) THEN IF stilling(stOff+ n-10)=wP THEN wbonus:=wbonus-BishopBeforePawn; END IF; END IF;
                    IF (n=13) AND (stilling(stOff+ 22)=wP) AND (stilling(stOff+ 24)<>spc) THEN wbonus:=wbonus-BishopBehindPawn; END IF;  
                    IF (n=16) AND (stilling(stOff+ 27)=wP) AND (stilling(stOff+ 25)<>spc) THEN wbonus:=wbonus-BishopBehindPawn; END IF;  
                    IF (stilling(stOff+ n-11)=wP) OR (stilling(stOff+ n-9)=wP) THEN wbonus:=wbonus+BishopProtectedByPawn; END IF;
        WHEN brik= wN     THEN 
                    matr:=matr+Value_S; knEndGameW:=TRUE;
                    IF (n<39) AND (n>30) THEN IF stilling(stOff+ n-10)=wP THEN wbonus:=wbonus-kNightBeforePawn; END IF; END IF;
                    IF (stilling(stOff+ n-11)=wP) OR (stilling(stOff+ n-9)=wP) THEN wbonus:=wbonus+kNightProtectedByPawn; END IF;
                    IF (stilling(stOff+ n+10)=bP) AND (stilling(stOff+ n+11)<>bP) AND (stilling(stOff+ n+9)<>bP) THEN
                      wbonus:=wbonus+kNightpPawnInFront;
                      IF (n>50) OR (stilling(stOff+ n+19)<>bP) AND (stilling(stOff+ n+21)<>bP) THEN 
                        wbonus:=wbonus+kNightpPawnInFront;
                        IF (n>60) OR (stilling(stOff+ n+29)<>bP) AND (stilling(stOff+ n+31)<>bP) THEN 
                          wbonus:=wbonus+kNightpPawnInFront;
                        END IF;
                      END IF;
                    END IF;
        WHEN brik IN (wP,wE) THEN matr:=matr+ValueB;
                    IF stilling(stOff+ n- 1)=wP THEN
                      IF EndGame THEN
                        IF n>70 THEN
                          wbonus:=wbonus+TwoOnRow7;
                        ELSIF n>60 THEN
                          wbonus:=wbonus+TwoOnRow6;
                        ELSIF n>50 THEN
                          wbonus:=wbonus+TwoOnRow5;
                        END IF;
                      END IF;
                      wbonus:=wbonus+PawnNextToPawn;
                    END IF;
                    IF stilling(stOff+ n+ 1)=wP THEN wbonus:=wbonus+PawnNextToPawn; END IF;
                    IF stilling(stOff+ n- 9)=wP THEN wbonus:=wbonus+PawnGuardsPawn; END IF;
                    IF stilling(stOff+ n-11)=wP THEN wbonus:=wbonus+PawnGuardsPawn; END IF;
                    IF stilling(stOff+ n-10)=wP THEN wbonus:=wbonus-PawnDoubbledPawn; END IF;
                    IF stilling(stOff+ n-20)=wP THEN wbonus:=wbonus-PawnDoubbledPawn; END IF;
        WHEN brik in (bR,bC) THEN 
                    matr:=matr-ValueT; KingEndGameB:=FALSE;
                    IF (n>40) THEN
                      IF (stilling(stOff+ n-10)=bP) OR (stilling(stOff+ n-20)=bP) THEN
                        bbonus:=bbonus-RookFirstRowBehindPawn;
                      END IF;
                    END IF;
                    IF n=81 THEN
                      IF brik=bC THEN matr:=matr+(ValueT-ValueR); END IF;
                      IF stilling(stOff+ 82)<>spc THEN
                        IF stilling(stOff+ 82)=bK THEN
                          bbonus:=bbonus-RookCornerNextToKing;
                        ELSE
                          bbonus:=bbonus-RookCornerNextToPiece;
                        END IF;
                      END IF;
                    ELSIF n=88 THEN
                      IF brik=bC THEN matr:=matr+(ValueT-ValueR); END IF;
                      IF stilling(stOff+ 87)<>spc THEN
                        IF stilling(stOff+ 87)=bK THEN
                          bbonus:=bbonus-RookCornerNextToKing;
                        ELSE
                          bbonus:=bbonus-RookCornerNextToPiece;
                        END IF;
                      END IF;
                    END IF;
        WHEN brik= bM     THEN 
                    matr:=matr-ValueM; Kpos:=n;
        WHEN brik= bK     THEN 
                    matr:=matr-ValueK; Kpos:=n;
                    IF NOT EndGame THEN
                      IF (n=86) AND ((stilling(stOff+ 88)=bR) OR (stilling(stOff+ 87)=bR))
                      OR (n=83) AND ((stilling(stOff+ 81)=bR) OR (stilling(stOff+ 82)=bR)) THEN
                        IF (n=86) AND (stilling(stOff+ 76)=bP) AND (stilling(stOff+ 77)=bP) 
                        OR (n=83) AND (stilling(stOff+ 73)=bP) AND (stilling(stOff+ 72)=bP) THEN
                          bbonus:=bbonus-KingCloseRook;
                        END IF;
                      ELSE
                        FOR m IN n-11..n-9 LOOP
                          IF stilling(stOff+ m)=bP THEN bbonus:=bbonus+KingBehindPawns; END IF;
                        END LOOP;
                        bbonus:=bbonus-KingBehindPawns;
                      END IF;
                    END IF;
        WHEN brik= bQ     THEN 
                    matr:=matr-ValueD; KingEndGameB:=FALSE;
                    IF OpenGame THEN
                      IF n<71 THEN
                        bbonus:=bbonus-12;
                        IF n<61 THEN
                           IF n<>51 THEN bbonus:=bbonus-QueenDeveloped; END IF;
                        ELSE
                          IF (n=64) AND (stilling(stOff+ 74)=bP) THEN
                            bbonus:=bbonus-QueenBeforePawn;
                            IF (stilling(stOff+ 83)=bB) AND (stilling(stOff+ 72)=bP) THEN
                              bbonus:=bbonus-QueenBeforePawnBlockedBishop;
                            END IF;
                          ELSIF (n=65) AND (stilling(stOff+ 75)=bP) THEN
                            bbonus:=bbonus-QueenBeforePawn;
                            IF (stilling(stOff+ 86)=bB) AND (stilling(stOff+ 77)=bP) THEN
                              bbonus:=bbonus-QueenBeforePawnBlockedBishop;
                            END IF;
                          END IF;
                        END IF;
                      ELSIF (n=74) AND (stilling(stOff+ 83)=bB) AND (stilling(stOff+ 72)=bP)
                      OR    (n=75) AND (stilling(stOff+ 86)=bB) AND (stilling(stOff+ 77)=bP) THEN
                        bbonus :=bbonus-QueenBeforeBishop;
                      END IF;
                    END IF;
        WHEN brik= bB     THEN 
                    matr:=matr-ValueL; KingEndGameB:=FALSE;bBishops:=bBishops+1;
                    IF (n>60) AND (n<69) THEN IF stilling(stOff+ n+10)=bP THEN bbonus:=bbonus-BishopBeforePawn; END IF; END IF;
                    IF (n=83) AND (stilling(stOff+ 72)=bP) AND (stilling(stOff+ 74)<>spc) THEN bbonus:=bbonus-BishopBehindPawn; END IF;  
                    IF (n=86) AND (stilling(stOff+ 77)=bP) AND (stilling(stOff+ 75)<>spc) THEN bbonus:=bbonus-BishopBehindPawn; END IF;  
                    IF (stilling(stOff+ n+11)=bP) OR (stilling(stOff+ n+9)=bP) THEN bbonus:=bbonus+BishopProtectedByPawn; END IF;
        WHEN brik= bN     THEN 
                    matr:=matr-Value_S; knEndGameB:=TRUE;
                    IF (n>60) AND (n<69) THEN IF stilling(stOff+ n+10)=bP THEN bbonus:=bbonus-kNightBeforePawn; END IF; END IF;
                    IF (stilling(stOff+ n+11)=bP) OR (stilling(stOff+ n+9)=bP) THEN bbonus:=bbonus+kNightProtectedByPawn; END IF;
                    IF (stilling(stOff+ n-10)=wP) AND (stilling(stOff+ n-11)<>wP) AND (stilling(stOff+ n-9)<>wP) THEN
                      bbonus:=bbonus+kNightpPawnInFront;
                      IF (n<31) OR (stilling(stOff+ n-19)<>wP) AND (stilling(stOff+ n-21)<>wP) THEN 
                        bbonus:=bbonus+kNightpPawnInFront;
                        IF (n<41) OR (stilling(stOff+ n-29)<>wP) AND (stilling(stOff+ n-31)<>wP) THEN 
                          bbonus:=bbonus+kNightpPawnInFront;
                        END IF;
                      END IF;
                    END IF;
        WHEN brik in (bP,bE) THEN 
                    matr:=matr-ValueB;
                    IF stilling(stOff+ n- 1)=bP THEN
                      IF EndGame THEN
                        IF n<29 THEN
                          bbonus:=bbonus+TwoOnRow7;
                        ELSIF n<39 THEN
                          bbonus:=bbonus+TwoOnRow6;
                        ELSIF n<49 THEN
                          bbonus:=bbonus+TwoOnRow5;
                        END IF;
                      END IF;
                      bbonus:=bbonus+PawnNextToPawn;
                    END IF;
                    IF stilling(stOff+ n+ 1)=bP THEN bbonus:=bbonus+PawnNextToPawn; END IF;
                    IF stilling(stOff+ n+ 9)=bP THEN bbonus:=bbonus+PawnGuardsPawn; END IF;
                    IF stilling(stOff+ n+11)=bP THEN bbonus:=bbonus+PawnGuardsPawn; END IF;
                    IF stilling(stOff+ n+10)=bP THEN bbonus:=bbonus-PawnDoubbledPawn; END IF;
                    IF stilling(stOff+ n+20)=bP THEN bbonus:=bbonus-PawnDoubbledPawn; END IF;
      ELSE
        NULL; 
      END CASE;
--(*$ IF Test0
--WRITEF(s('POSI (')+l(posi)+c(')'));
--(*$ENDIF
      IF brik=UPPER_n(brik) THEN 
        posi:=posi-pd(pdN(brik,n)); -- 99-n
      ELSE 
        posi:=posi+pd(pdN(brik,n)); -- UPPER_n(brik)
      END IF;
--(*$ IF Test0
--WRITELNF(s(' brik=')+c(brik)+s(' n=')+l(n)+s(' posi=')+l(posi));
--(*$ENDIF
    END IF;
  END LOOP;
  IF wBishops = 2 THEN wbonus:=wbonus+BishopPairBonus*OpenCenterDegree; END IF;
  IF bBishops = 2 THEN bbonus:=bbonus+BishopPairBonus*OpenCenterDegree; END IF;

  --short-cut experiment (no detailed eval if more than 300 better than nessecary
  -- Makes it just one % faster and serches 2% more positions. NO change in strength, so 
  -- Not a good complication:
  --IF matr<alpha-300 OR matr>beta+300 THEN
  --      IF Black THEN
  --        return -matr-posi-wbonus+bbonus -inmv;
  --       ELSE
  --        return  matr+posi+wbonus-bbonus +inmv;     
  --      END IF;
  --END IF;

  IF (KingEndGameW OR KingEndGameB) AND ABS(matr+posi+wbonus-bbonus) < 800 THEN --dont use energy to more exact endgame-evaluations in totally won/lost positions (100= one pawn)
    IF knEndGameW THEN priW:=knEndGamePrio; ELSE priW:=knEndGamePrio*2; END IF;
    IF knEndGameB THEN priB:=knEndGamePrio; ELSE priB:=knEndGamePrio*2; END IF;
    --WRT('KingEndgame '||CASE WHEN KingEndGameW THEN 'W' END||','||CASE WHEN KingEndGameB THEN bP END);
    --FOR yy IN 1..8 LOOP
    --  DebugS := edge;
    --  FOR xx IN 1..8 LOOP
    --    DebugS := DebugS||stilling(stOff+ xx+10*(9-yy));
    --  END LOOP;
    --  WRT(DebugS);
    --END LOOP;
    --WRT('matr='||matr||' wbonus='||wbonus||' bbonus='||bbonus||' posi='||posi); --matr=-1559 wbonus=-3 bbonus=24 posi=-33
    --WRT(stilling(stOff+ hvistur));
    IF NOT pawnsInit THEN
      Wpawns.extend(89);
      Bpawns.extend(89);
      WpL.extend(8);
      BpL.extend(8);
      pawnsInit := TRUE;
    END IF;
    
    FOR n IN 11..88 LOOP
      Wpawns(n):=FALSE;
      Bpawns(n):=FALSE;
    END LOOP;

    FOR x IN 1..8 LOOP WpL(x):=0; BpL(x):=0; END LOOP;
    WpLc:=0; BpLc:=0;
    -- mark squares with pawn defend
    FOR y IN 2..7 LOOP
      FOR x IN 1..8 LOOP
        n:=10*y+x;
        ch := stilling(stOff+ n);
        CASE 
         WHEN ch in (bP,bE) THEN 
                    IF KingEndGameB THEN
                      BpL(x) := BpL(x) + 1;
                      BpLc := BpLc + 1;
                      Bpawns(n-10):=TRUE;
                      IF NOT HvidsTur THEN 
                        Bpawns(n-11):=TRUE; -- 10 too!
                        Bpawns(n- 9):=TRUE;
                      END IF;
                      --FOR m IN 20+x..n-20 BY 10 LOOP
                      FOR m_n in 2..y-2 LOOP --testet grundígt!!!
                        m := m_n*10+x;
                        Bpawns(m)  :=TRUE;
                        Bpawns(m-1):=TRUE;
                        Bpawns(m+1):=TRUE;
                      END LOOP;
                    END IF;
        WHEN ch in (wP,wE)  THEN 
                    IF KingEndGameW THEN
                      WpL(x) := WpL(x) + 1;
                      WpLc := WpLc+1;
                      Wpawns(n+10):=TRUE;
                      IF HvidsTur THEN 
                        Wpawns(n+11):=TRUE; -- 89 too!
                        Wpawns(n+ 9):=TRUE;
                      END IF;
                      --FOR m IN n+20..70+x BY 10 LOOP
                      FOR m_n in 2+y..7 LOOP--testet grundígt!!!
                        m := m_n*10+x;
                        Wpawns(m)  :=TRUE;
                        Wpawns(m-1):=TRUE;
                        Wpawns(m+1):=TRUE;
                      END LOOP;
                    END IF;
        ELSE 
          NULL;
        END CASE;
      END LOOP;
    END LOOP;

    -- find first (nearest promotion) free white pawn
    IF KingEndGameB THEN
      Slut:=FALSE;
      --IF NOT knEndGameB AND (posi<0) THEN -- Check if only pawns on A or H file
      --  -- IF king in the corner then equal !!!!!!! VIRKER VIST IKKE!!!!!*)
      --  IF (BpLc=BpL(8)) AND ((kposs=17) OR (kposs=18) OR (kposs=27) OR (kposs=28)) 
      --  OR (BpLc=BpL(1)) AND ((kposs=12) OR (kposs=11) OR (kposs=22) OR (kposs=21)) THEN
      --    RETURN(0);
      --  END IF;
      --END IF;
      <<outer_y1>>
      FOR y_n IN 3..7 LOOP--FOR y IN 7..3 BY -1 
        y := 10 - y_n;
        FOR x IN 1..8 LOOP
          n:=10*y+x;
          IF (stilling(stOff+ n)=wP) OR (y=3) AND (stilling(stOff+ n-10)=wP) THEN
            IF NOT Bpawns(n) THEN
              IF (FLOOR(Kpos/10)<y) OR (ABS( MOD(Kpos,10-x))>8-y) THEN
                Slut:=TRUE; -- inside quadrant
              ELSIF NOT knEndGameB THEN
                IF (n>60) THEN
                  IF (kposs=n+9) OR (kposs=n+11) THEN
                    Slut:=TRUE; -- Supported pawn
                  ELSIF n>70 THEN
                    IF (kposs=n-1) OR (kposs=n+1)
                    OR (kposs=n-12) AND (kposs<=n-8) AND (Kpos<>n+10) THEN
                      Slut:=TRUE; -- Supported pawn
                    END IF;
                  ELSE
                    IF (kposs=n-1) AND (MOD(Kpos,10)>x)
                    OR (kposs=n+1) AND (MOD(Kpos,10)<x) THEN
                      Slut:=TRUE; -- Supported pawn in one move
                      posi:=posi-SupportedPawnPenalty;
                    END IF;
                  END IF;
                ELSIF (n>50) THEN
                  -- IF Possibly supported pawn then add value:
                  IF (kposs=n+9)  OR (kposs=n+11) THEN posi:=posi+ SupportedPawn0911; END IF;
                  IF (kposs=n+10) OR (kposs=n+20) THEN posi:=posi+ SupportedPawn1020; END IF;
                  IF (kposs=n+19) OR (kposs=n+21) THEN posi:=posi+ SupportedPawn1921; END IF;
                END IF;
              END IF;
              IF Slut THEN
                posi:=posi+y*y*priW; 
                exit outer_y1;--x:=8; y:=3; -- pawn can promote, exit loop
--(*$ IF Test0 --WRITELNF(s(' fpW felt=')+l(n)+s(' posi=')+l(posi)); --(*$ ENDIF
              END IF;
            END IF;
          END IF;
        END LOOP;
      END LOOP outer_y1;
    END IF;
    -- find first (nearest promotion) free black pawn
    IF KingEndGameW THEN
      Slut:=FALSE;
      --IF NOT knEndGameW AND (posi>0) THEN -- Check if only pawns on A or H file
      --  -- IF king in the corner then equal !!!!!!! MAY NOT WORK!!!!!
      --  IF (WpLc=WpL(8)) AND ((Kpos=87) OR (Kpos=88) OR (Kpos=77) OR (Kpos=78)) 
      --  OR (WpLc=WpL(1)) AND ((Kpos=72) OR (Kpos=71) OR (Kpos=72) OR (Kpos=71)) THEN
      --    RETURN(0);
      --  END IF;
      --END IF;
      <<outer_y2>>
      FOR y IN 2..6 LOOP
        FOR x IN 1..8 LOOP
          n:=10*y+x;
          IF (stilling(stOff+ n)=bP) OR (y=6) AND (stilling(stOff+ n+10)=bP) THEN
            IF NOT Wpawns(n) THEN
              IF (FLOOR(kposs/10)-1>y) OR (ABS(MOD(kposs,10)-x)>y) THEN
                Slut:=TRUE; -- inside quadrant
              ELSIF NOT knEndGameW THEN
                IF (n<40) THEN
                  IF (Kpos=n-9) OR (Kpos=n-11) THEN
                    Slut:=TRUE; -- Supported pawn
                  ELSIF n<30 THEN
                    IF (Kpos=n-1) OR (Kpos=n+1)
                    OR (Kpos>=n+12) AND (Kpos<=n+8) AND (kposs<>n-10) THEN
                      Slut:=TRUE; -- Supported pawn
                    END IF;
                  ELSE
                    IF (Kpos=n-1) AND (MOD(kposs,10)>x)
                    OR (Kpos=n+1) AND (MOD(kposs, 10)<x) THEN
                      Slut:=TRUE; -- Supported pawn in one move
                      posi:=posi+SupportedPawnPenalty;
                    END IF;
                  END IF;
                ELSIF (n<50) THEN
                  -- IF Possibly supported pawn then add value:
                  IF (Kpos=n-9)  OR (Kpos=n-11) THEN posi:=posi- SupportedPawn0911; END IF;
                  IF (Kpos=n-10) OR (Kpos=n-20) THEN posi:=posi- SupportedPawn1020; END IF;
                  IF (Kpos=n-19) OR (Kpos=n-21) THEN posi:=posi- SupportedPawn1921; END IF;
                END IF;
              END IF;
              IF Slut THEN
                posi:=posi-(9-y)*(9-y)*priB; 
                exit outer_y2;-- x:=8; y:=6; -- pawn can promote, exit loop
--(*$ IF Test0  --WRITELNF(s(' fpB felt=')+l(n)+s(' posi=')+l(posi)); --(*$ ENDIF
              END IF;
            END IF;
          END IF;
        END LOOP;
      END LOOP outer_y2;
    END IF;
          
  END IF;

  IF TRUE THEN-- EndGame OR (matr>alpha-200) AND (matr<beta+200) THEN
    -- penalty for bad development
    m:=-1;
    IF stilling(stOff+ 12)=wN THEN m := m + 1; END IF;
    IF stilling(stOff+ 13)=wB THEN m := m + 1; END IF;
    IF stilling(stOff+ 15)=wM THEN
      m := m + 1;
      IF stilling(stOff+ 16)=wB THEN wbonus:=wbonus-BadDevelBishop; END IF;
    END IF;
    IF stilling(stOff+ 16)=wB THEN m := m + 1; END IF;
    IF stilling(stOff+ 17)=wN THEN m := m + 1; END IF;
    IF stilling(stOff+ 24)=wP THEN m := m + 1; END IF;
    IF stilling(stOff+ 25)=wP THEN m := m + 1; END IF;
    IF m>0 THEN wbonus:=wbonus-m*BadDevelPenalty; END IF;
    m:=-1;
    IF stilling(stOff+ 82)=bN THEN m := m + 1; END IF;
    IF stilling(stOff+ 83)=bB THEN m := m + 1; END IF;
    IF stilling(stOff+ 85)=bM THEN
      m := m + 1;
      IF stilling(stOff+ 86)=bB THEN bbonus:=bbonus-BadDevelBishop; END IF;
    END IF;
    IF stilling(stOff+ 86)=bB THEN m := m + 1; END IF;
    IF stilling(stOff+ 87)=bN THEN m := m + 1; END IF;
    IF stilling(stOff+ 74)=bP THEN m := m + 1; END IF;
    IF stilling(stOff+ 75)=bP THEN m := m + 1; END IF;
    IF m>0 THEN bbonus:=bbonus-m*BadDevelPenalty; END IF;

--(*$ IF Test0
--  tst2('Eval:',stilling,bK);
--(*$ ENDIF

    IF Black THEN
--(*$ IF Test --WRITELNF(s(' !!SORT!! ')); --(*$ ENDIF
  
      res:=(-matr-posi-wbonus+bbonus /* +Activity*ActivityWeight */ -inmv);
    ELSE
      res:=( matr+posi+wbonus-bbonus /* +Activity*ActivityWeight */ +inmv);
    END IF; --** posi DIV 2 !!!!!!!!!****)
    
    IF PawnOfficer THEN
      IF endgame and ABS(res) > 180 THEN -- in front, so bonus for pawns and penalty for Officers
        m := 0; 
        IF ABS(res) > 540 THEN
          n := 4;
        ELSIF ABS(res) > 360 THEN
          n := 3;
        ELSE
          n := 2;
        END IF;
        FOR y IN 1..8 LOOP
          FOR x IN 1..8 LOOP
            brik:=UPPER_n(stilling(stOff+ 10*y+x));
            CASE brik
              WHEN bQ THEN m := m - 17*n;
              WHEN bR THEN m := m - 9*n;
              WHEN bC THEN m := m - 9*n;
              WHEN bN THEN m := m - 6*n;
              WHEN bB THEN m := m - 6*n;
              WHEN bP THEN m := m + 4*n;
              WHEN bE THEN m := m + 4*n;
              ELSE NULL;
            END CASE;        
          END LOOP;
        END LOOP;
        --m:=m*5;
        IF res < 0 THEN
          res := res - m;
        ELSE
          res := res + m;
        END IF;   
        --IF TRAPon THEN WRT('In front Officers penalty+pawns bonus (keep pawns and exchange officers)='||m); END IF;
      END IF;
    END IF;

  ELSE
    IF Black THEN RETURN(-matr); ELSE RETURN(matr); END IF;
  END IF;
  --
/*
DECLARE
  english BOOLEAN := FALSE;
  ch CHAR(1);
BEGIN
    WRT('.  _______________________________');
    FOR yy IN 1..8 LOOP
      DebugS :=' '||to_char(9-yy)||' | ';
      FOR xx IN 1..8 LOOP
        DebugS := DebugS||stilling(stOff+ xx+10*(9-yy))||' | ';
      END LOOP;
      IF english THEN --english version will not show castling-rights and en-passant.
        DebugS:= TRANSLATE(DebugS,'BbEeLlSsDdTt',
                                  'PpPpBbNnQqRr');
      END IF;
      WRT(DebugS);
      WRT('.  -------------------------------');
    END LOOP;
    ch := stilling(stOff+ PL_PIG_CHESS_ENGINE.HvisTur );
    WRT('.   A   B   C   D   E   F   G   H   '''||CASE WHEN english THEN CASE when ch=bN THEN bP ELSE 'W' END ELSE ch END||'''');
END;
WRT('res='||res||' matr='||matr||' wbonus='||wbonus||' bbonus='||bbonus||' posi='||posi||'  '||stilling(stOff+ hvistur)); --matr=-1559 wbonus=-3 bbonus=24 posi=-33
*/
  -- 
  RETURN(res);
END Eval;



PROCEDURE Initialize IS
 n SIMPLE_INTEGER := 0;
BEGIN
  IF not FirstW THEN
    ToFile:=TRUE;
    FirstW:=TRUE;
    --LogVersion("SkakBrainEval.def",SkakBrainEvalDefCompilation);
    --LogVersion("SkakBrainEval.mod",SkakBrainEvalModCompilation);
    -- dbms_output.put_line('Initialize A');
     pdw.extend(pdSz);
    -- dbms_output.put_line('Initialize B');
    FOR n in 1..pdSz LOOP
      pdw(n) := 0;
    END LOOP;
    --dbms_output.put_line('Initialize C');
    pd  := pdw;
    pdb := pdw;
    --WRT('Initialize EVAL');
  ELSE
    NULL;
    --WRT('Initialize EVAL SKIP');
  END IF;
END Initialize;

END;
/
