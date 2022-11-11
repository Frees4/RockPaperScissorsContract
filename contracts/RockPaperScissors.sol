// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract RockPaperScissors {
    enum GameState {
        JoinPhase,
        CommitPhase,
        RevealPhase,
        ResultPhase
    }

    enum GameResult {
        P1Win,
        P2Win,
        Draw
    }
    // Hashes of options
    bytes32 rockHash = keccak256(abi.encodePacked("rock"));
    bytes32 paperHash = keccak256(abi.encodePacked("paper"));
    bytes32 scissorsHash = keccak256(abi.encodePacked("scissors"));

    event CreateGame(address gameHash, address player1, address player2);
    event ChoiceMade(address player, bytes32 choice);
    event Played(address game, bytes32 p1Choice, bytes32 p2Choice, GameResult result);

    struct GameStruct {
        bool initialized;
        address player1;
        address player2;
        GameState gameState;
        bytes32 commit1;
        bytes32 commit2;
        bytes32 reveal1;
        bytes32 reveal2;
        uint256 revealDeadline;
        GameResult gameResult;
    }

    mapping(address => GameStruct) public games;
    mapping(address => address) public activeGame;

    modifier validGameState(address gameHash, GameState gameState) {
        require(
            games[gameHash].initialized == true,
            "Game code does not exist"
        );
        require(
            games[gameHash].player1 == msg.sender ||
                games[gameHash].player2 == msg.sender,
            "Player not in this game"
        );
        require(
            games[gameHash].gameState == gameState,
            "Game not in correct phase"
        );
        _;
    }

    function createGame(address otherPlayer) public returns (address) {
        address gameHash = generateGameHash();
        require(
            !games[gameHash].initialized,
            "Game code already exists, please try again"
        );
        // Check other player isn't host
        require(
            msg.sender != otherPlayer,
            "Invited player must have a different address"
        );

        games[gameHash].initialized = true;
        games[gameHash].player1 = msg.sender;
        games[gameHash].player2 = otherPlayer;

        games[gameHash].gameState = GameState.JoinPhase;

        activeGame[msg.sender] = gameHash;
        emit CreateGame(gameHash, games[gameHash].player1, games[gameHash].player2);

        return gameHash;
    }

    function joinGame(address gameHash)
        public
        validGameState(gameHash, GameState.JoinPhase)
    {
        games[gameHash].gameState = GameState.CommitPhase;

        activeGame[msg.sender] = gameHash;
    }

    function commit(string memory choice, string memory salt)
        public
        validGameState(activeGame[msg.sender], GameState.CommitPhase)
    {
        address gameHash = activeGame[msg.sender];

        bytes32 unsaltedChoiceHash = keccak256(abi.encodePacked(choice));

        require(
            unsaltedChoiceHash == rockHash ||
                unsaltedChoiceHash == paperHash ||
                unsaltedChoiceHash == scissorsHash,
            "Invalid choice. Please select 'rock', 'paper' or 'scissors'"
        );

        bytes32 commitHash = keccak256(abi.encodePacked(choice, salt));

        bool isPlayer1 = games[gameHash].player1 == msg.sender;
        if (isPlayer1) {
            games[gameHash].commit1 = commitHash;
            emit ChoiceMade(games[gameHash].player1, games[gameHash].commit1);
        } else {
            games[gameHash].commit2 = commitHash;
            emit ChoiceMade(games[gameHash].player2, games[gameHash].commit2);
        }

        if (games[gameHash].commit1 != 0 && games[gameHash].commit2 != 0) {
            games[gameHash].gameState = GameState.RevealPhase;
        }
    }

    function reveal(string memory salt)
        public
        validGameState(activeGame[msg.sender], GameState.RevealPhase)
    {
        address gameHash = activeGame[msg.sender];

        bool isPlayer1 = games[gameHash].player1 == msg.sender;
        if (isPlayer1) {
            require(games[gameHash].reveal1 == 0, "Already revealed");
        } else {
            require(games[gameHash].reveal2 == 0, "Already revealed");
        }

        bytes32 verificationHashRock = keccak256(
            abi.encodePacked("rock", salt)
        );
        bytes32 verificationHashPaper = keccak256(
            abi.encodePacked("paper", salt)
        );
        bytes32 verificationHashScissors = keccak256(
            abi.encodePacked("scissors", salt)
        );

        bytes32 commitHash = isPlayer1
            ? games[gameHash].commit1
            : games[gameHash].commit2;

        require(
            verificationHashRock == commitHash ||
                verificationHashPaper == commitHash ||
                verificationHashScissors == commitHash,
            "Reveal hash doesn't match commit hash. Salt not the same as commit."
        );

        string memory choice;
        if (verificationHashRock == commitHash) {
            choice = "rock";
        } else if (verificationHashPaper == commitHash) {
            choice = "paper";
        } else {
            choice = "scissors";
        }

        if (isPlayer1) {
            games[gameHash].reveal1 = keccak256(abi.encodePacked(choice));
        } else {
            games[gameHash].reveal2 = keccak256(abi.encodePacked(choice));
        }

        if (games[gameHash].reveal1 != 0 && games[gameHash].reveal2 != 0) {
            games[gameHash].gameResult = determineWinner(
                games[gameHash].reveal1,
                games[gameHash].reveal2
            );
            games[gameHash].gameState = GameState.ResultPhase;
        } else {
            games[gameHash].revealDeadline = block.timestamp + 3 minutes;
        }
    }

    function determineDefaultWinner()
        public
        validGameState(activeGame[msg.sender], GameState.RevealPhase)
    {
        address gameHash = activeGame[msg.sender];

        games[gameHash].gameResult = determineWinner(
            games[gameHash].reveal1,
            games[gameHash].reveal2
        );
        games[gameHash].gameState = GameState.ResultPhase;
        emit Played(msg.sender, games[gameHash].reveal1, games[gameHash].reveal2, games[gameHash].gameResult);
    }

    function leaveGame() public {
        activeGame[msg.sender] = address(0);
    }

    function generateGameHash() public view returns (address) {
        bytes32 prevHash = blockhash(block.number - 1);
        return
            address(bytes20(keccak256(abi.encodePacked(prevHash, msg.sender))));
    }

    function determineWinner(bytes32 revealP1, bytes32 revealP2)
        public
        view
        returns (GameResult)
    {
        if (revealP1 != 0 && revealP2 != 0) {
            if (revealP1 == revealP2) {
                return GameResult.Draw;
            }
            if (revealP1 == rockHash) {
                if (revealP2 == scissorsHash) {
                    return GameResult.P1Win;
                } else {
                    return GameResult.P2Win;
                }
            } else if (revealP1 == paperHash) {
                if (revealP2 == rockHash) {
                    return GameResult.P1Win;
                } else {
                    return GameResult.P2Win;
                }
            } else {
                if (revealP2 == paperHash) {
                    return GameResult.P1Win;
                } else {
                    return GameResult.P2Win;
                }
            }
        }
        else if (revealP1 != 0) {
            return GameResult.P1Win;
        } else {
            return GameResult.P2Win;
        }
    }

    function getActiveGameData(address player)
        public
        view
        returns (GameStruct memory)
    {
        address gameHash = activeGame[player];
        return games[gameHash];
    }
}