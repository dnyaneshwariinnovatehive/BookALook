import 'dart:math' as math;
import 'more_menu_catalog.dart';

/// Represents a scored search result from the More tab catalog.
class MoreSearchResult {
  final MoreMenuItem item;
  final int score;
  final String matchedField;

  const MoreSearchResult({
    required this.item,
    required this.score,
    this.matchedField = '',
  });
}

/// Advanced local search matching and relevance ranking engine for More Tab.
///
/// Designed to feel identical to Instagram Settings search:
/// - Case-insensitive & punctuation-resilient matching.
/// - Exact, prefix, substring, and multi-word phrase matching.
/// - Synonym and keyword indexing for natural language phrases.
/// - Conservative typo tolerance (Levenshtein distance <= 1 for tokens >= 4 chars).
/// - Deterministic relevance scoring.
class MoreSearchEngine {
  /// Searches [items] against [query] and returns results ordered by relevance.
  static List<MoreSearchResult> search({
    required String query,
    required List<MoreMenuItem> items,
  }) {
    final cleanQuery = _normalize(query);
    if (cleanQuery.isEmpty) return const [];

    final queryTokens = cleanQuery
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    final results = <MoreSearchResult>[];

    // Deduplicate items by ID if any repeated instances exist
    final seenIds = <String>{};
    final uniqueItems = items.where((it) => seenIds.add(it.id)).toList();

    for (final item in uniqueItems) {
      final scoreResult = _scoreItem(item, cleanQuery, queryTokens);
      if (scoreResult.score > 0) {
        results.add(
          MoreSearchResult(
            item: item,
            score: scoreResult.score,
            matchedField: scoreResult.matchedField,
          ),
        );
      }
    }

    // Sort descending by score, tie-break by original catalogue position
    results.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.item.title.compareTo(b.item.title);
    });

    return results;
  }

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ') // replace punctuation with space
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static _ScoringResult _scoreItem(
    MoreMenuItem item,
    String cleanQuery,
    List<String> queryTokens,
  ) {
    int totalScore = 0;
    String bestField = '';

    final titleNorm = _normalize(item.title);
    final descNorm = _normalize(item.subtitle);
    final catNorm = _normalize(item.category);
    final keywordsNorm = item.keywords.map(_normalize).toList();

    // 1. Exact Title Match (+1000)
    if (titleNorm == cleanQuery) {
      return _ScoringResult(1000, 'title_exact');
    }

    // 2. Title Starts With Query (+500)
    if (titleNorm.startsWith(cleanQuery)) {
      totalScore += 500;
      bestField = 'title_prefix';
    }
    // 3. Title Contains Complete Query Phrase (+300)
    else if (titleNorm.contains(cleanQuery)) {
      totalScore += 300;
      bestField = 'title_contains';
    }

    // 4. Keyword Matches
    bool matchedExactKeyword = false;
    bool matchedPrefixKeyword = false;
    bool matchedPartialKeyword = false;

    for (final kw in keywordsNorm) {
      if (kw == cleanQuery) {
        matchedExactKeyword = true;
        break;
      } else if (kw.startsWith(cleanQuery)) {
        matchedPrefixKeyword = true;
      } else if (kw.contains(cleanQuery)) {
        matchedPartialKeyword = true;
      }
    }

    if (matchedExactKeyword) {
      totalScore += 250;
      if (bestField.isEmpty) bestField = 'keyword_exact';
    } else if (matchedPrefixKeyword) {
      totalScore += 180;
      if (bestField.isEmpty) bestField = 'keyword_prefix';
    } else if (matchedPartialKeyword) {
      totalScore += 120;
      if (bestField.isEmpty) bestField = 'keyword_contains';
    }

    // 5. Multi-Token Coverage
    // When the query has multiple words (e.g. "first time offer", "staff salary", "working hours"),
    // check whether all words appear in the item's title, keywords, category or description.
    if (queryTokens.length > 1) {
      int matchedTokensCount = 0;
      for (final token in queryTokens) {
        final matchesTitle = titleNorm.contains(token);
        final matchesKw = keywordsNorm.any((kw) => kw.contains(token));
        final matchesDesc = descNorm.contains(token);
        final matchesCat = catNorm.contains(token);

        if (matchesTitle || matchesKw || matchesDesc || matchesCat) {
          matchedTokensCount++;
        }
      }

      if (matchedTokensCount == queryTokens.length) {
        totalScore += 200; // All tokens present
      } else if (matchedTokensCount > 0) {
        totalScore += (matchedTokensCount * 30);
      }
    }

    // 6. Description / Category Substring Matches
    if (descNorm.contains(cleanQuery)) {
      totalScore += 60;
      if (bestField.isEmpty) bestField = 'description';
    }
    if (catNorm.contains(cleanQuery)) {
      totalScore += 40;
      if (bestField.isEmpty) bestField = 'category';
    }

    // 7. Typo Tolerance (Levenshtein Distance <= 1 for tokens >= 4 characters)
    // Only applied if no strong match has been found yet
    if (totalScore == 0) {
      for (final token in queryTokens) {
        if (token.length >= 4) {
          // Check title words
          final titleWords = titleNorm.split(' ');
          for (final tw in titleWords) {
            if (tw.length >= 4 && _levenshtein(token, tw) <= 1) {
              totalScore += 80;
              bestField = 'title_typo';
              break;
            }
          }

          // Check keywords
          if (totalScore == 0) {
            for (final kw in keywordsNorm) {
              final kwWords = kw.split(' ');
              for (final kwWord in kwWords) {
                if (kwWord.length >= 4 && _levenshtein(token, kwWord) <= 1) {
                  totalScore += 60;
                  bestField = 'keyword_typo';
                  break;
                }
              }
              if (totalScore > 0) break;
            }
          }
        }
      }
    }

    return _ScoringResult(totalScore, bestField);
  }

  /// Calculates the Levenshtein edit distance between two strings.
  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.generate(t.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        v1[j + 1] = math.min(v1[j] + 1, math.min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v0[t.length];
  }
}

class _ScoringResult {
  final int score;
  final String matchedField;
  const _ScoringResult(this.score, this.matchedField);
}
