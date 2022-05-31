
import 'package:logger/logger.dart';
import 'package:tinode/src/database/objectbox.g.dart';

import 'model.dart';

class ObjectBox {

  static const int DEFAULT_MESSAGE_LIMIT = 20;

  static const int DEFAULT_MESSAGE_THRESHOLD_IN_TOPIC = 10000000;

  late final Store store;

  late final Box<DataMessage> dataMessageBox;

  final _logger = Logger();

  List<DataMessage> getMessagesWith(String topic, {int? offset, int? limit}) {
    final msgBox = store.box<DataMessage>();
    final builder = msgBox.query(DataMessage_.topic.equals(topic))..order(DataMessage_.seq, flags: Order.descending);
    final query = builder.build()
      ..offset = offset ?? 0
      ..limit = limit ?? DEFAULT_MESSAGE_LIMIT;
    final res = query.find();
    query.close();
    return res;
  }

  void updateMessage(String topic, DataMessage data) {
    final topicBox = store.box<LocalTopic>();
    final msgBox = store.box<DataMessage>();
    final query = topicBox.query(LocalTopic_.name.equals(topic)).build();
    try {
      var localTopic = query.findFirst();
      int topicId;
      if(localTopic == null) {
        localTopic ??= LocalTopic(topic);
        topicId = topicBox.put(localTopic);
      } else {
        topicId = localTopic.id;
      }
      final headData = data.head;
      if (headData != null) {
        if(headData.containsKey('reaction_to') && headData.containsKey('reaction')) {
          final updatedId = headData['reaction_to'];
          final reactions = headData['reaction'];
          final id = topicId * DEFAULT_MESSAGE_THRESHOLD_IN_TOPIC + updatedId as int;
          final msg = msgBox.get(id);
          if(msg != null) {
            msg.head?['reaction'] = reactions;
            msgBox.put(msg);
          }
        }
        if(headData.containsKey('answer_to') && headData.containsKey('answers')) {
          final updatedId = headData['answer_to'];
          final answers = headData['answers'];
          final id = topicId * DEFAULT_MESSAGE_THRESHOLD_IN_TOPIC + updatedId as int;
          final msg = msgBox.get(id);
          if (msg != null) {
            if (msg.head?.containsKey('data') == true) {
              msg.head?['data']['answers'] = answers;
            }
            msgBox.put(msg);
          }
        }
      }
    } catch(e) {
      _logger.i('ObjectBox#Error Update Message = ${e.toString()}');
    } finally {
      query.close();
    }
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
        msg.id = topicId * DEFAULT_MESSAGE_THRESHOLD_IN_TOPIC + (msg.seq ?? 0);
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
