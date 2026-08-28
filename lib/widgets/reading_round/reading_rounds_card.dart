import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_round.dart';
import 'package:anx_reader/providers/reading_round_provider.dart';
import 'package:anx_reader/service/reading_round_service.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 多刷阅读统计：书籍详情页的「阅读轮次」卡片
///
/// 展示当前轮次状态、已完成轮次的历史统计，并提供
/// 【完成本轮，开始下一刷】与【撤销】两个交互按钮。
class ReadingRoundsCard extends ConsumerWidget {
  const ReadingRoundsCard({
    super.key,
    required this.book,
    required this.onRoundFinished,
  });

  final Book book;

  /// 完成/撤销轮次后回调（父页面用于刷新书籍状态）
  final ValueChanged<Book> onRoundFinished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roundsAsync = ref.watch(readingRoundsProvider(book.id));
    return FilledContainer(
      width: MediaQuery.of(context).size.width,
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      child: AsyncSkeletonWrapper<List<ReadingRound>>(
        enabled: false,
        asyncValue: roundsAsync,
        builder: (rounds, _) => _buildContent(context, ref, rounds),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, List<ReadingRound> rounds) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final finishedRounds = rounds.where((r) => r.isFinished).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.readingRoundsSectionTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        _buildCurrentRound(context),
        const Divider(height: 24),
        if (finishedRounds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              l10n.readingRoundsEmpty,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          )
        else
          ...finishedRounds.reversed.map((r) => _buildRoundTile(context, r)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _confirmFinishRound(context, ref),
                icon: const Icon(Icons.restart_alt),
                label: Text(l10n.readingRoundsFinishAndStartNext),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: book.currentRound > 1
                  ? () => _undoLastRound(context, ref)
                  : null,
              icon: const Icon(Icons.undo),
              label: Text(l10n.readingRoundsUndo),
            ),
          ],
        ),
      ],
    );
  }

  /// 当前轮次：轮次号 + 状态 + 本轮累计时长 + 当前进度
  Widget _buildCurrentRound(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return FutureBuilder<int>(
      future: readingTimeDao.selectTotalReadingTimeByBookAndRound(
          book.id, book.currentRound),
      builder: (context, snapshot) {
        final duration = convertSeconds(snapshot.data ?? 0);
        final progress = (book.readingPercentage * 100).toStringAsFixed(1);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_stories, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l10n.readingRoundsCurrentRound}：'
                    '${l10n.readingRoundsNth('${book.currentRound}')} · '
                    '${l10n.readingRoundsInProgress}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.readingRoundsDuration}：$duration    '
                    '${l10n.readingRoundsProgress}：$progress%',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 已完成轮次的统计条目
  Widget _buildRoundTile(BuildContext context, ReadingRound round) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final startDate = (round.startTime?.length ?? 0) >= 10
        ? round.startTime!.substring(0, 10)
        : '?';
    final endDate =
        (round.endTime?.length ?? 0) >= 10 ? round.endTime!.substring(0, 10) : '?';
    final startPct = (round.startPercentage * 100).toStringAsFixed(0);
    final endPct = (round.endPercentage * 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                '${l10n.readingRoundsNth('${round.roundNumber}')} · '
                '${l10n.readingRoundsFinished}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$startDate ~ $endDate',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          Text(
            '${l10n.readingRoundsDuration}：${convertSeconds(round.totalReadingTime)}    '
            '${l10n.readingRoundsProgress}：$startPct% → $endPct%',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmFinishRound(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.readingRoundsConfirmTitle),
        content: Text(l10n.readingRoundsConfirmContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.readingRoundsConfirmOk),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final updated = await ReadingRoundService.finishCurrentRound(book);
    if (!context.mounted) return;
    ref.read(readingRoundsProvider(book.id).notifier).refresh();
    onRoundFinished(updated);
    AnxToast.show(l10n.readingRoundsFinishedToast(
        '${updated.currentRound - 1}', '${updated.currentRound}'));
  }

  Future<void> _undoLastRound(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final updated = await ReadingRoundService.undoLastRound(book);
    if (!context.mounted) return;
    ref.read(readingRoundsProvider(book.id).notifier).refresh();
    onRoundFinished(updated);
    AnxToast.show(l10n.readingRoundsUndoToast('${updated.currentRound}'));
  }
}
