import 'dart:async';
import 'package:flutter/material.dart';

class AnimatedSearchField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final List<String> suggestions;

  const AnimatedSearchField({
    Key? key,
    required this.controller,
    required this.suggestions,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.style,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  }) : super(key: key);

  @override
  State<AnimatedSearchField> createState() => _AnimatedSearchFieldState();
}

class _AnimatedSearchFieldState extends State<AnimatedSearchField> {
  Timer? _timer;
  int _wordIndex = 0;
  String _currentHint = "";
  bool _isTyping = true;
  bool _isActive = true;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _startAnimation();
  }

  void _onTextChanged() {
    if (widget.controller.text.isNotEmpty) {
      _stopAnimation();
    } else {
      _startAnimation();
    }
  }

  void _stopAnimation() {
    if (!_isActive) return;
    _timer?.cancel();
    if (mounted) {
      setState(() {
        _isActive = false;
        _currentHint = "";
      });
    }
  }

  void _startAnimation() {
    if (_isActive || widget.suggestions.isEmpty) return;
    if (mounted) {
      setState(() {
        _isActive = true;
        _wordIndex = 0;
        _currentHint = "";
        _isTyping = true;
      });
    }
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    if (!mounted || !_isActive || widget.suggestions.isEmpty) return;

    final currentWord = widget.suggestions[_wordIndex % widget.suggestions.length];

    if (_isTyping) {
      if (_currentHint.length < currentWord.length) {
        _timer = Timer(const Duration(milliseconds: 70), () {
          if (!mounted || !_isActive) return;
          setState(() {
            _currentHint = currentWord.substring(0, _currentHint.length + 1);
          });
          _scheduleNextTick();
        });
      } else {
        _isTyping = false;
        _timer = Timer(const Duration(milliseconds: 1200), _scheduleNextTick);
      }
    } else {
      if (_currentHint.isNotEmpty) {
        _timer = Timer(const Duration(milliseconds: 40), () {
          if (!mounted || !_isActive) return;
          setState(() {
            _currentHint = _currentHint.substring(0, _currentHint.length - 1);
          });
          _scheduleNextTick();
        });
      } else {
        _isTyping = true;
        _wordIndex++;
        _timer = Timer(const Duration(milliseconds: 300), _scheduleNextTick);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.suggestions.isNotEmpty
        ? 'Search "$_currentHint"'
        : widget.decoration.hintText;

    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      style: widget.style,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration.copyWith(
        hintText: hint,
      ),
    );
  }
}
