import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/reading_round.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_round.dart';

/// 多刷阅读统计：轮次管理服务
///
/// 流程：
/// 1. 阅读中：时长按 (book_id, date, round) 入库，并累加到 tb_reading_rounds
/// 2. 用户点击【完成本轮】：
///    - 当前轮记录写入结束快照（end_time / end_percentage / total_reading_time）
///    - book.currentRound + 1，阅读进度与位置归零
///    - 新建下一轮记录（status=reading, start_percentage=0）
class ReadingRoundService {
  ReadingRoundService._();

  /// 完成当前轮，开启下一轮；返回更新后的 [Book]
  static Future<Book> finishCurrentRound(Book book) async {
    final currentRound = book.currentRound;

    // 1. 确保当前轮记录存在（可能从未在详情页打开过）
    await readingRoundDao.ensureCurrentRound(
      bookId: book.id,
      roundNumber: currentRound,
      startPercentage: book.readingPercentage,
    );

    // 2. 本轮累计时长（按 tb_reading_time 实际记录汇总）
    final totalTime =
        await readingTimeDao.selectTotalReadingTimeByBookAndRound(
            book.id, currentRound);

    // 3. 写入当前轮结束快照
    final current = await readingRoundDao.getCurrentRound(book.id);
    if (current != null && current.isFinished == false) {
      await readingRoundDao.finishRound(
        current.id!,
        endPercentage: book.readingPercentage,
        totalReadingTime: totalTime,
      );
    }

    // 4. 开启下一轮：轮次 +1，进度/位置归零，新建记录
    final nextRound = currentRound + 1;
    await readingRoundDao.createRound(
      bookId: book.id,
      roundNumber: nextRound,
      startPercentage: 0,
    );

    final updated = book.copyWith(
      currentRound: nextRound,
      lastReadPosition: '',
      readingPercentage: 0,
    );
    await bookDao.updateBook(updated);
    return updated;
  }

  /// 撤销最近一次【完成本轮】（误触保护）：
  /// 删除进行中的新轮记录，轮次号回退，并尽量恢复上一轮结束时的进度。
  /// 返回更新后的 [Book]；无可回退时返回原 [book]。
  static Future<Book> undoLastRound(Book book) async {
    if (book.currentRound <= 1) {
      return book;
    }

    final previousRound = book.currentRound - 1;
    final rounds = await readingRoundDao.selectRoundsByBookId(book.id);

    // 找到上一轮的完成快照，用于恢复进度
    double restoredPercentage = 0;
    for (final r in rounds) {
      if (r.roundNumber == previousRound && r.isFinished) {
        restoredPercentage = r.endPercentage;
        break;
      }
    }

    // 删除当前进行中的轮次记录
    final current = await readingRoundDao.getCurrentRound(book.id);
    if (current != null && current.id != null) {
      await readingRoundDao.delete(ReadingRoundDao.table,
          where: 'id = ?', whereArgs: [current.id]);
    }

    final updated = book.copyWith(
      currentRound: previousRound,
      readingPercentage: restoredPercentage,
      lastReadPosition: '',
    );
    await bookDao.updateBook(updated);
    return updated;
  }

  /// 撤销后重新确认当前轮记录存在（避免空记录导致详情页异常）
  static Future<void> ensureRoundRecord(int bookId, int roundNumber,
      {double startPercentage = 0}) async {
    await readingRoundDao.ensureCurrentRound(
      bookId: bookId,
      roundNumber: roundNumber,
      startPercentage: startPercentage,
    );
  }
}
