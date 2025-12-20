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
  int startOfTurnScore = 0;
  int legsWon;
  int setsWon;
  int totalPointsScoredForAverage = 0;
  int totalDartsForAverage = 0;
  List<int> currentThrowHistory;

  double get average {
    if (totalDartsForAverage == 0) return 0.0;
    return (totalPointsScoredForAverage / totalDartsForAverage) * 3;
  }

  Player({
    required this.name,
    this.currentScore = 501,
    this.legsWon = 0,
    this.setsWon = 0,
  }) : currentThrowHistory = [];
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
  final int maxSets = 3;
  int legStarterIndex = 0;

  int currentPlayerIndex = 0;
  int currentModifier = 1; // 1 = Single, 2 = Double, 3 = Triple

  // State
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

  void startGame() {
    players = playerNames.map((name) => Player(name: name)).toList();
    for (var p in players) {
      p.startOfTurnScore = 501; // Initialwert
    }
    currentPlayerIndex = 0;
    legStarterIndex = 0;
    notifyListeners();
  }

  // Audio
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

    // Wurf zur History hinzufügen
    p.currentThrowHistory.add(points);

    int tempScore = p.currentScore - points;

    // --- BUST LOGIK ---
    if (tempScore < 0 || tempScore == 1) {
      _handleBust(); // Hier wird intern der Score resetet und _nextTurn gerufen
      currentModifier = 1;
      notifyListeners();
      return; // Methode SOFORT beenden
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

    // Sound Check (Andi)
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

    // Aufnahme beendet (3 Darts geworfen)
    if (p.currentThrowHistory.length == 3) {
      _finalizeTurnStats(p, false);
      _nextTurn();
    }

    currentModifier = 1; // Reset Modifier nach jedem Wurf
    notifyListeners();
  }

  // Hilfsmethode für den sauberen Average
  void _finalizeTurnStats(Player p, bool isBust) {
    // Bei einem Bust zählen die Punkte der Aufnahme als 0
    int pointsToAdd = isBust
        ? 0
        : p.currentThrowHistory.reduce((a, b) => a + b);

    p.totalPointsScoredForAverage += pointsToAdd;
    p.totalDartsForAverage += p.currentThrowHistory.length;
  }

  void undoLastThrow() {
    Player p = activePlayer;

    // Wenn in der aktuellen Aufnahme schon Darts geworfen wurden:
    if (p.currentThrowHistory.isNotEmpty) {
      int lastValue = p.currentThrowHistory.removeLast();
      p.currentScore += lastValue; // Punkte zurückgeben
    }
    // Wenn die Aufnahme leer ist, zum vorherigen Spieler zurückwechseln
    else {
      currentPlayerIndex = (currentPlayerIndex - 1) % players.length;
      // Falls der Index negativ wird (bei Spieler 0):
      if (currentPlayerIndex < 0) currentPlayerIndex = players.length - 1;

      // Hier müsste man eigentlich noch die History des vorherigen Spielers laden
      // Für den Anfang reicht das Zurücksetzen innerhalb einer Aufnahme.
    }

    notifyListeners();
  }

  Future<void> _safePlay(String fileName) async {
    try {
      // Vorher stoppen, falls noch ein Sound läuft (verhindert Überlagerungsfehler im Web)
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/$fileName'));
    } catch (e) {
      print("Audio Fehler bei $fileName: $e");
      // Hier könnte man eine Fallback-Logik einbauen
    }
  }

  void setModifier(int mod) {
    if (currentModifier == mod) {
      currentModifier = 1; // Toggle off
    } else {
      currentModifier = mod;
    }
    notifyListeners();
  }

  void _handleBust() async {
    Player p = activePlayer;
    p.currentScore = p.startOfTurnScore;

    _finalizeTurnStats(p, true);
    //TODO bust sound
    await Future.delayed(const Duration(milliseconds: 500));
    await _safePlay('bust.mp3');

    _nextTurn();
  }

  void _handleMatchWin() {
    if (navigatorKey.currentContext == null) return;

    // Diese Methode im GameState aufrufen, wenn setsWon == maxSets
    showDialog(
      context: navigatorKey.currentContext!,
      // Erfordert einen globalen NavigatorKey
      builder: (context) => AlertDialog(
        title: const Text("Match gewonnen!"),
        content: Text(
          "${activePlayer.name} hat gewonnen!\nAverage: ${activePlayer.average.toStringAsFixed(2)}",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(
                context,
              ).popUntil((route) => route.isFirst); // Zurück zum Setup
            },
            child: const Text("Neues Spiel"),
          ),
        ],
      ),
    );
  }

  void _handleLegWin() {
    activePlayer.legsWon++;

    if (activePlayer.legsWon >= legsPerSet) {
      // ... (deine Sets-Logik bleibt gleich)
      activePlayer.setsWon++;
      activePlayer.legsWon = 0;
      for (var p in players) p.legsWon = 0;

      if (activePlayer.setsWon >= maxSets) {
        _handleMatchWin();
        return;
      }
    }

    // 1. Scores für alle zurücksetzen
    for (var p in players) {
      p.currentScore = startingScore;
      p.currentThrowHistory.clear();
      p.startOfTurnScore = startingScore;
    }

    // 2. ANWURF-WECHSEL LOGIK
    // Wir wechseln den Starter des Legs (0 -> 1 oder 1 -> 0)
    legStarterIndex = (legStarterIndex + 1) % players.length;

    // Der neue aktuelle Spieler ist der neue Leg-Starter
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
    // Zugriff auf den State
    var state = context.watch<GameState>();
    var activePlayer = state.activePlayer;

    return Scaffold(
      appBar: AppBar(title: const Text("Dart Counter 501")),
      body: Column(
        children: [
          // --- SCOREBOARD ---
          Expanded(
            flex: 2,
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
                    vertical: 10,
                    horizontal: 5,
                  ),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.blueGrey[700] : Colors.grey[900],
                    borderRadius: BorderRadius.circular(15),
                    border: isActive
                        ? Border.all(color: Colors.amber, width: 3)
                        : Border.all(color: Colors.transparent),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.3),
                              blurRadius: 10,
                            ),
                          ]
                        : [],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 22,
                          color: Colors.white70,
                        ),
                      ),
                      Text(
                        "${p.currentScore}",
                        style: const TextStyle(
                          fontSize: 70,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      // --- AVERAGE ANZEIGE ---
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "Ø: ${p.average.toStringAsFixed(2)}",
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Sets: ${p.setsWon} | Legs: ${p.legsWon}",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(height: 5),
                        Text(
                          "Darts: ${p.currentThrowHistory.join('  ')}",
                          style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
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
                vertical: 8.0,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green[900],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "Checkout: ${CheckoutService.getCheckoutHint(activePlayer.currentScore) ?? 'Kein gängiger Weg'}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          const Divider(color: Colors.grey, thickness: 1),

          // --- INPUT PAD (Tablet optimiert) ---
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // Linke Spalte: Große Modifier-Tasten
                Container(
                  width: 160,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildModifierBtn(
                        context,
                        "DOUBLE",
                        2,
                        state.currentModifier == 2,
                        Colors.orange,
                      ),
                      const SizedBox(height: 12),
                      _buildModifierBtn(
                        context,
                        "TRIPLE",
                        3,
                        state.currentModifier == 3,
                        Colors.redAccent,
                      ),
                      const SizedBox(height: 12),
                      _buildUndoBtn(context),
                    ],
                  ),
                ),

                // Rechte Seite: Das Zahlen-Grid
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 7,
                    padding: const EdgeInsets.all(12),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
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
    return Expanded(
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? activeColor : Colors.grey[800],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            side: isActive
                ? const BorderSide(color: Colors.white, width: 3)
                : null,
            elevation: isActive ? 10 : 2,
          ),
          onPressed: () => context.read<GameState>().setModifier(val),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildUndoBtn(BuildContext context) {
    return Expanded(
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.amber, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            backgroundColor: Colors.amber.withOpacity(0.05),
          ),
          onPressed: () => context.read<GameState>().undoLastThrow(),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.undo, color: Colors.amber, size: 30),
              Text(
                "UNDO",
                style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
