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
    super.key,
    required this.controller,
    required this.suggestions,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.style,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  State<AnimatedSearchField> createState() => _AnimatedSearchFieldState();
}

class _AnimatedSearchFieldState extends State<AnimatedSearchField> with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _wordIndex = 0;
  String _currentHint = "";
  bool _isTyping = true;
  bool _isActive = true;
  late FocusNode _focusNode;
  late AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
    
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
    
    _startAnimation();
  }

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
      if (_focusNode.hasFocus) {
        _stopAnimation();
      } else {
        if (widget.controller.text.isEmpty) {
          _startAnimation();
        }
      }
    }
  }

  void _onTextChanged() {
    if (mounted) {
      setState(() {});
      if (widget.controller.text.isNotEmpty || _focusNode.hasFocus) {
        _stopAnimation();
      } else {
        _startAnimation();
      }
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
        _timer = Timer(const Duration(milliseconds: 1300), _scheduleNextTick);
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
    _cursorController.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChanged);
    }
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showAnimatedHint = widget.controller.text.isEmpty && !_focusNode.hasFocus && widget.suggestions.isNotEmpty;
    
    final TextStyle baseStyle = widget.style ?? const TextStyle(fontSize: 14);
    final TextStyle hintStyle = widget.decoration.hintStyle ?? baseStyle.copyWith(color: Colors.grey);
    
    Widget hintLayer = const SizedBox.shrink();
    if (showAnimatedHint) {
       hintLayer = IgnorePointer(
         child: Padding(
           padding: widget.decoration.contentPadding ?? EdgeInsets.zero,
           child: Row(
             mainAxisSize: MainAxisSize.min,
             children: [
               Text('Search "', style: hintStyle),
               Text(_currentHint, style: hintStyle),
               AnimatedBuilder(
                 animation: _cursorController,
                 builder: (context, child) {
                   return Opacity(
                     opacity: _currentHint.isEmpty ? 0.0 : _cursorController.value,
                     child: Container(
                       width: 1.5,
                       height: hintStyle.fontSize != null ? hintStyle.fontSize! * 1.2 : 16,
                       color: hintStyle.color ?? Colors.grey,
                       margin: const EdgeInsets.symmetric(horizontal: 0.5),
                     ),
                   );
                 }
               ),
               Text('"', style: hintStyle),
             ],
           ),
         ),
       );
    }

    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        if (showAnimatedHint) hintLayer,
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          style: widget.style,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          textInputAction: widget.textInputAction,
          decoration: widget.decoration.copyWith(
            hintText: showAnimatedHint ? '' : widget.decoration.hintText,
          ),
        ),
      ],
    );
  }
}
