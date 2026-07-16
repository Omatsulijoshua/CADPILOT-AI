import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'models.dart';

const _patternHashKey = 'cadpilot.reentryPatternHash.v1';

String _hashPattern(List<int> pattern) =>
    sha256.convert(utf8.encode(pattern.join('-'))).toString();

class ReentryLock extends StatefulWidget {
  const ReentryLock({required this.session, super.key});

  final Session session;

  @override
  State<ReentryLock> createState() => _ReentryLockState();
}

class _ReentryLockState extends State<ReentryLock> {
  String? _savedHash;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _savedHash = prefs.getString(_patternHashKey);
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_savedHash == null) {
      return PatternSetup(
        session: widget.session,
        onComplete: (hash) => setState(() => _savedHash = hash),
      );
    }
    return PatternUnlock(session: widget.session, expectedHash: _savedHash!);
  }
}

class PatternSetup extends StatefulWidget {
  const PatternSetup({required this.session, required this.onComplete, super.key});
  final Session session;
  final ValueChanged<String> onComplete;

  @override
  State<PatternSetup> createState() => _PatternSetupState();
}

class _PatternSetupState extends State<PatternSetup> {
  List<int>? _firstPattern;
  String _message = 'Create a pattern to protect this signed-in device.';

  Future<void> _submit(List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() => _message = 'Connect at least four dots.');
      return;
    }
    if (_firstPattern == null) {
      setState(() {
        _firstPattern = pattern;
        _message = 'Repeat the same pattern to confirm it.';
      });
      return;
    }
    if (_firstPattern!.join() != pattern.join()) {
      setState(() {
        _firstPattern = null;
        _message = 'Patterns did not match. Create a new pattern.';
      });
      return;
    }
    final hash = _hashPattern(pattern);
    await (await SharedPreferences.getInstance()).setString(_patternHashKey, hash);
    widget.onComplete(hash);
  }

  @override
  Widget build(BuildContext context) => LockScaffold(
        title: 'Protect CadPilot',
        message: _message,
        footer: TextButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => Dashboard(session: widget.session)),
          ),
          child: const Text('Not now'),
        ),
        child: PatternPad(onComplete: _submit),
      );
}

class PatternUnlock extends StatefulWidget {
  const PatternUnlock({required this.session, required this.expectedHash, super.key});
  final Session session;
  final String expectedHash;

  @override
  State<PatternUnlock> createState() => _PatternUnlockState();
}

class _PatternUnlockState extends State<PatternUnlock> {
  String _message = 'Draw your pattern to unlock your workspace.';

  void _unlock(List<int> pattern) {
    if (_hashPattern(pattern) == widget.expectedHash) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => Dashboard(session: widget.session)),
      );
    } else {
      setState(() => _message = 'That pattern is incorrect. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) => LockScaffold(
        title: 'Welcome back',
        message: _message,
        child: PatternPad(onComplete: _unlock),
      );
}

class LockScaffold extends StatelessWidget {
  const LockScaffold({required this.title, required this.message, required this.child, this.footer, super.key});
  final String title;
  final String message;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SizedBox(
            width: 420,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(36),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/branding/cadpilot-icon-master.png', width: 74, height: 74),
                  const SizedBox(height: 18),
                  Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 26),
                  child,
                  if (footer != null) ...[const SizedBox(height: 12), footer!],
                ]),
              ),
            ),
          ),
        ),
      );
}

class PatternPad extends StatefulWidget {
  const PatternPad({required this.onComplete, super.key});
  final ValueChanged<List<int>> onComplete;

  @override
  State<PatternPad> createState() => _PatternPadState();
}

class _PatternPadState extends State<PatternPad> {
  final List<int> _pattern = [];

  void _tap(int dot) {
    if (_pattern.contains(dot)) return;
    setState(() => _pattern.add(dot));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          width: 240,
          height: 240,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 9,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
            itemBuilder: (context, index) {
              final dot = index + 1;
              final selected = _pattern.contains(dot);
              return InkWell(
                borderRadius: BorderRadius.circular(48),
                onTap: () => _tap(dot),
                child: Center(child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: selected ? 36 : 22,
                  height: selected ? 36 : 22,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xff29d3b2) : const Color(0xff62727e),
                    shape: BoxShape.circle,
                  ),
                )),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text('${_pattern.length} dots selected'),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          TextButton(onPressed: () => setState(_pattern.clear), child: const Text('Clear')),
          const SizedBox(width: 12),
          FilledButton(onPressed: _pattern.isEmpty ? null : () { final value = List<int>.from(_pattern); setState(_pattern.clear); widget.onComplete(value); }, child: const Text('Continue')),
        ]),
      ]);
}
