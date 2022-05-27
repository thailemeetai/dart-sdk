import 'package:logger/logger.dart';
import 'package:tinode/src/database/objectbox.g.dart';

import 'model.dart';

class ObjectBox {

  static const int DEFAULT_MESSAGE_LIMIT = 20;

  late final Store store;

  late final Box<DataMessage> dataMessageBox;

  Stream<Query<DataMessage>>? queryStream;
  Query<DataMessage>? query;

  final _logger = Logger();

  Stream<Query<DataMessage>> getMessageStream(String topic) {
    if(queryStream == null) {
      final qBuilder = dataMessageBox.query(DataMessage_.topic.equals(topic))..order(DataMessage_.seq); //, flags: Order.descending
      queryStream = qBuilder.watch(triggerImmediately: true);
    }
    return queryStream!;
  }

  Query<DataMessage>? getMessageStreamQuery(String topic) {
    final msgBox = store.box<DataMessage>();
    final builder = msgBox.query(DataMessage_.topic.equals(topic))..order(DataMessage_.seq);
    // builder.watch(triggerImmediately: true);
    // return builder.build();
    query = builder.build();
    query!..limit = 20
          ..offset = 0;
    return query;
  }

  void addDataMessage(DataMessage message) {
    final topic = message.topic ?? '';
    final seq = message.seq ?? 0;
    final combinedId = '${topic}_$seq';

    final query = dataMessageBox.query(DataMessage_.combinedId.equals(combinedId)).build();
    final existingMsg = query.findFirst();

    _logger.i('ObjectBox#Add Single combinedId = $combinedId');
    if(existingMsg == null) {
      store.runInTransactionAsync(TxMode.write, _addDataMessageInTx, message);
    }

  }

  static void _addDataMessageInTx(Store store, DataMessage data) {
    store.box<DataMessage>().put(data); // write 17 -> crash
    // store.box<DataMessage>().putQueued(data); write 30 -> crash
    // store.box<DataMessage>().putAsync(data); // write 39 -> crash

    // store.box<DataMessage>().put(object)
  }

  Future<void> addDataMessages(List<DataMessage> messages, {int? offset}) async {
    _logger.i('ObjectBox#Add Batch size = ${messages.length} - offset = $offset');
    if(messages.isEmpty) return;
    final topic = messages[0].topic ?? '';
    // final query = dataMessageBox.query(DataMessage_.topic.equals(topic)).build()
    //       ..limit = DEFAULT_MESSAGE_LIMIT
    //       ..offset = offset ?? 0;
    // final list = query.find();
    // final unInsertedMessages = <DataMessage>[];
    // for(final rawMsg in messages) {
    //   final rawCombinedId = '${rawMsg.topic}_${rawMsg.seq}';
    //   if (!list.any((e) => e.combinedId == rawCombinedId)) {
    //     unInsertedMessages.add(rawMsg);
    //   }
    // }
    // try {
    //   await store.runInTransactionAsync(TxMode.write, _putMessagesInTx, unInsertedMessages);
    // } catch (e) {
    //   _logger.i('ObjectBox#Error Add Batch = ${e.toString()}');
    // }

    final topicBox = store.box<LocalTopic>();
    final msgBox = store.box<DataMessage>();
    final query2 = topicBox.query(LocalTopic_.name.equals(topic)).build();
    try {
      var localTopic = query2.findFirst();
      int topicId;
      if(localTopic == null) {
        localTopic ??= LocalTopic(topic);
        topicId = topicBox.put(localTopic);
      } else {
        topicId = localTopic.id;
      }

      for(final msg in messages) {
        msg.id = topicId * 10000000 + (msg.seq ?? 0);
        msgBox.put(msg);
        // Then can safely add target Object to ToMany
        localTopic.messages.add(msg);
      }
      topicBox.put(localTopic);
    } catch(e) {
      _logger.i('ObjectBox#Error Add Batch = ${e.toString()}');
    } finally {
      query2.close();
    }
  }

  void clearAll() {
    // dataMessageBox.removeAll();
  }

  static void _putMessagesInTx(Store store, List<DataMessage> messages) =>
      store.box<DataMessage>().putMany(messages);

  /// Create an instance of ObjectBox to use throughout the app.
  static Future<ObjectBox> create() async {
    final store = await openStore();
    return ObjectBox._create(store);
  }

  ObjectBox._create(this.store) {
    dataMessageBox = Box<DataMessage>(store);
  }

}
