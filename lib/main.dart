import 'package:audioplayers/audioplayers.dart';
import 'package:dart_app/checkouts.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// --------------------------------------------------------------------------
// 1. DATA MODELS & CONSTANTS (Die "Java POJOs")
// --------------------------------------------------------------------------

class Player {
  final String name;
  int currentScore;
  int startOfTurnScore = 501;
  int legsWon;
  int setsWon;

  int totalPointsScoredForAverage = 0;
  int totalDartsForAverage = 0;

  List<int> currentThrowHistory = [];

  List<int> turnHistory = [];

  Player({
    required this.name,
    this.currentScore = 501,
    this.legsWon = 0,
    this.setsWon = 0,
  });

  double get average {
    if (totalDartsForAverage == 0) return 0.0;
    return (totalPointsScoredForAverage / totalDartsForAverage) * 3;
  }

  void resetLegStats(int startingScore) {
    currentScore = startingScore;
    startOfTurnScore = startingScore;
    totalPointsScoredForAverage = 0;
    totalDartsForAverage = 0;
    currentThrowHistory.clear();
    turnHistory.clear();
  }
}

class CheckoutService {
  static String? getCheckoutHint(int score) {
    return dartFinishes[score];
  }
}

// --------------------------------------------------------------------------
// 2. LOGIC / STATE MANAGEMENT (Der "Game Controller")
// --------------------------------------------------------------------------

class GameState extends ChangeNotifier {
  // Settings
  final int startingScore = 501;
  final int legsPerSet = 3;
  final int maxSets = 1;
  int legStarterIndex = 0;

  int currentPlayerIndex = 0;
  int currentModifier = 1; // 1 = Single, 2 = Double, 3 = Triple

  List<Player> players = [];

  List<String> playerNames = ["Moritz"];

  void addPlayerName(String name) {
    if (name.isNotEmpty) {
      playerNames.add(name);
      notifyListeners();
    }
  }

  void removePlayerName(int index) {
    if (playerNames.length > 1) {
      playerNames.removeAt(index);
      notifyListeners();
    }
  }

  void startGame() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _safePlay('game-start.mp3');

    players = playerNames.map((name) => Player(name: name)).toList();
    for (var p in players) {
      p.startOfTurnScore = 501;
    }
    currentPlayerIndex = 0;
    legStarterIndex = 0;
    notifyListeners();
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  Player get activePlayer => players[currentPlayerIndex];

  void processThrow(int baseScore) async {
    int points = baseScore * currentModifier;
    Player p = activePlayer;

    if (baseScore == 25 && currentModifier == 3) {
      currentModifier = 1;
      notifyListeners();
      return;
    }

    p.currentThrowHistory.add(points);

    int tempScore = p.currentScore - points;

    // --- BUST LOGIK ---
    if (tempScore < 0 || tempScore == 1) {
      _handleBust();
      currentModifier = 1;
      notifyListeners();
      return;
    }
    // --- CHECKOUT LOGIK ---
    else if (tempScore == 0) {
      if (currentModifier == 2 || (baseScore == 25 && currentModifier == 2)) {
        p.currentScore = 0;
        _finalizeTurnStats(p, false);
        _handleLegWin();
        return;
      } else {
        _handleBust();
        currentModifier = 1;
        notifyListeners();
        return;
      }
    }
    // --- NORMALER WURF ---
    else {
      p.currentScore = tempScore;
    }

    if (p.currentThrowHistory.length == 3) {
      int sumOfTurn = p.currentThrowHistory.reduce((a, b) => a + b);
      if (sumOfTurn == 26) {
        await Future.delayed(const Duration(milliseconds: 500));

        int timestamp = DateTime.now().millisecondsSinceEpoch;
        if (timestamp % 2 == 0) {
          await _safePlay('classic-andi.mp3');
        } else {
          await _safePlay('classic-eni.mp3');
        }
      }
    }

    if (p.currentThrowHistory.length == 3) {
      _finalizeTurnStats(p, false);
      _nextTurn();
    }

    currentModifier = 1;
    notifyListeners();
  }

  void _finalizeTurnStats(Player p, bool isBust) {
    int pointsToAdd = isBust
        ? 0
        : p.currentThrowHistory.reduce((a, b) => a + b);

    p.totalPointsScoredForAverage += pointsToAdd;
    p.totalDartsForAverage += p.currentThrowHistory.length;

    p.turnHistory.add(pointsToAdd);
  }

  void undoLastThrow() {
    Player p = activePlayer;

    if (p.currentThrowHistory.isNotEmpty) {
      int lastValue = p.currentThrowHistory.removeLast();
      p.currentScore += lastValue;
    } else {
      currentPlayerIndex = (currentPlayerIndex - 1) % players.length;
      if (currentPlayerIndex < 0) currentPlayerIndex = players.length - 1;
    }

    notifyListeners();
  }

  Future<void> _safePlay(String fileName) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/$fileName'));
    } catch (e) {
      print("Audio Fehler bei $fileName: $e");
    }
  }

  void setModifier(int mod) {
    if (currentModifier == mod) {
      currentModifier = 1;
    } else {
      currentModifier = mod;
    }
    notifyListeners();
  }

  void _handleBust() async {
    Player p = activePlayer;
    p.currentScore = p.startOfTurnScore;

    _finalizeTurnStats(p, true);
    await Future.delayed(const Duration(milliseconds: 500));
    await _safePlay('bust.mp3');

    _nextTurn();
  }

  void _handleMatchWin() {
    if (navigatorKey.currentContext == null) return;

    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text("Match gewonnen!"),
        content: Text(
          "${activePlayer.name} hat gewonnen!\nAverage: ${activePlayer.average.toStringAsFixed(2)}",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text("Neues Spiel"),
          ),
        ],
      ),
    );
  }

  void _handleLegWin() async {
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    await Future.delayed(const Duration(milliseconds: 500));
    if (activePlayer.name == "Moritz") {
      await _safePlay('leg-win-moritz.mp3');
    } else if (timestamp % 2 == 0) {
      await _safePlay('leg-win-andere.mp3');
    } else {
      await _safePlay('leg-win-doppel.mp3');
    }

    activePlayer.legsWon++;
    currentModifier = 1;

    if (activePlayer.legsWon >= legsPerSet) {
      activePlayer.setsWon++;
      activePlayer.legsWon = 0;
      for (var p in players) {
        p.legsWon = 0;
      }
      if (activePlayer.setsWon >= maxSets) {
        _handleMatchWin();
        return;
      }
    }
    for (var p in players) {
      p.resetLegStats(startingScore);
    }

    legStarterIndex = (legStarterIndex + 1) % players.length;
    currentPlayerIndex = legStarterIndex;
    notifyListeners();
  }

  void _nextTurn() {
    activePlayer.currentThrowHistory.clear();
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;

    activePlayer.startOfTurnScore = activePlayer.currentScore;
  }
}

// --------------------------------------------------------------------------
// 3. UI (WIDGETS)
// --------------------------------------------------------------------------

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => GameState(),
      child: const DartApp(),
    ),
  );
}

class DartApp extends StatelessWidget {
  const DartApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Dart Counter',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF222222), // Dark Mode Look
        textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.white)),
      ),
      home: SetupScreen(),
    );
  }
}

class SetupScreen extends StatelessWidget {
  final TextEditingController _controller = TextEditingController();

  SetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var state = context.watch<GameState>();

    return Scaffold(
      appBar: AppBar(title: const Text("Dart Setup")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Eingabefeld
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Spielername hinzufügen",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    state.addPlayerName(_controller.text);
                    _controller.clear();
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Liste der Spieler
            Expanded(
              child: ListView.builder(
                itemCount: state.playerNames.length,
                itemBuilder: (ctx, i) => ListTile(
                  title: Text(
                    state.playerNames[i],
                    style: const TextStyle(color: Colors.white),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => state.removePlayerName(i),
                  ),
                ),
              ),
            ),
            // Start Button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () {
                state.startGame();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const GameScreen()),
                );
              },
              child: const Text("SPIEL STARTEN"),
            ),
          ],
        ),
      ),
    );
  }
}

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    var state = context.watch<GameState>();
    var activePlayer = state.activePlayer;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: state.players.asMap().entries.map((entry) {
                int idx = entry.key;
                Player p = entry.value;
                bool isActive = idx == state.currentPlayerIndex;

                return Container(
                  width:
                      MediaQuery.of(context).size.width /
                      (state.players.length + 0.5),
                  margin: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 4,
                  ),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.blueGrey[700] : Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: isActive
                        ? Border.all(
                            color: Colors.amber,
                            width: 2,
                          ) // Rand dünner
                        : Border.all(color: Colors.transparent),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.3),
                              blurRadius: 8,
                            ),
                          ]
                        : [],
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.white70,
                          ),
                        ),

                        // Score
                        Text(
                          "${p.currentScore}",
                          style: const TextStyle(
                            fontSize: 45,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),

                        // Average Label
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "Ø: ${p.average.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        // Historie
                        Text(
                          "Letzte:",
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey[400],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 4,
                          children: p.turnHistory.reversed.take(5).map((score) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: _getScoreColor(score),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                "$score",
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 4),
                        Text(
                          "Sets: ${p.setsWon} | Legs: ${p.legsWon}",
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                        ),

                        if (isActive)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              "Darts: ${p.currentThrowHistory.join('  ')}",
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // --- CHECKOUT HINT ---
          if (activePlayer.currentScore <= 170)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Checkout: ${CheckoutService.getCheckoutHint(activePlayer.currentScore) ?? '...'}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          const Divider(color: Colors.grey, height: 1),
          // --- INPUT PAD ---
          Expanded(
            flex: 7,
            child: Row(
              children: [
                Container(
                  width: 140,
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      _buildModifierBtn(
                        context,
                        "DOUBLE",
                        2,
                        state.currentModifier == 2,
                        Colors.orange,
                      ),
                      const SizedBox(height: 8),
                      _buildModifierBtn(
                        context,
                        "TRIPLE",
                        3,
                        state.currentModifier == 3,
                        Colors.redAccent,
                      ),
                      const SizedBox(height: 8),
                      _buildUndoBtn(context),
                    ],
                  ),
                ),

                // Rechte Seite (Zahlen)
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 7,
                    padding: const EdgeInsets.all(8),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.3,
                    children: [
                      ...List.generate(
                        20,
                        (index) => _buildNumBtn(context, index + 1),
                      ),
                      _buildNumBtn(
                        context,
                        25,
                        label: "BULL",
                        color: Colors.green[700],
                      ),
                      _buildNumBtn(
                        context,
                        0,
                        label: "0",
                        color: Colors.blueGrey[800],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- HELPER WIDGETS ---

  Widget _buildNumBtn(
    BuildContext context,
    int value, {
    String? label,
    Color? color,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? Colors.grey[850],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 5,
      ),
      onPressed: () => context.read<GameState>().processThrow(value),
      child: Text(
        label ?? "$value",
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildModifierBtn(
    BuildContext context,
    String label,
    int val,
    bool isActive,
    Color activeColor,
  ) {
    return AspectRatio(
      aspectRatio: 2.0,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? activeColor : Colors.grey[800],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            side: isActive
                ? const BorderSide(color: Colors.white, width: 3)
                : null,
            elevation: isActive ? 10 : 2,
            padding:
                EdgeInsets.zero,
          ),
          onPressed: () => context.read<GameState>().setModifier(val),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildUndoBtn(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.0,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.amber, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            backgroundColor: Colors.amber.withOpacity(0.05),
            padding: EdgeInsets.zero,
          ),
          onPressed: () => context.read<GameState>().undoLastThrow(),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.undo, color: Colors.amber, size: 24),
              Text(
                "UNDO",
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _getScoreColor(int score) {
  if (score >= 100) return Colors.redAccent;
  if (score >= 60) return Colors.orangeAccent;
  if (score >= 40) return Colors.blueAccent;
  return Colors.grey[700]!;
}
