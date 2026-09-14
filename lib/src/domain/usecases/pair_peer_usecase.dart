import '../repositories/chat_repository.dart';

class PairPeerUseCase {
  const PairPeerUseCase(this._repository);

  final ChatRepository _repository;

  Future<void> connect(String peerId) => _repository.connectToPeer(peerId);

  Future<void> accept(String peerId) => _repository.acceptIncomingConnection(peerId);

  Future<void> reject(String peerId) => _repository.rejectIncomingConnection(peerId);

  Future<bool> verifyPin(String peerId, String pin) =>
      _repository.verifyPairingPin(peerId, pin);

  Future<bool> verifyQr(String rawQr) => _repository.verifyPairingQr(rawQr);

  Future<void> disconnect(String peerId) => _repository.disconnectPeer(peerId);
}
