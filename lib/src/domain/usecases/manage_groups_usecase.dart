import '../entities/chat_group_entity.dart';
import '../repositories/chat_repository.dart';

class ManageGroupsUseCase {
  const ManageGroupsUseCase(this._repository);

  final ChatRepository _repository;

  Future<ChatGroupEntity> createGroup({
    required String name,
    String description = '',
    required List<String> memberIds,
  }) =>
      _repository.createGroup(
        name: name,
        description: description,
        memberIds: memberIds,
      );
}
