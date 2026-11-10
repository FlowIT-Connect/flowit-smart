import 'package:flutter_test/flutter_test.dart';
import 'package:flowit_smart/core/camera_talk.dart';

void main() {
  test('voix vers la caméra : seule le G.711 est proposé (A-law d\'abord)', () {
    const offer = 'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 0 8 13 110 126\r\na=rtpmap:111 opus/48000/2\r\na=rtcp-fb:111 transport-cc\r\na=fmtp:111 minptime=10;useinbandfec=1\r\na=rtpmap:0 PCMU/8000\r\na=rtpmap:8 PCMA/8000\r\na=rtpmap:126 telephone-event/8000\r\na=sendonly\r\n';
    final sdp = onlyG711(offer);
    expect(sdp, contains('m=audio 9 UDP/TLS/RTP/SAVPF 8 0'));
    expect(sdp, isNot(contains('opus')));
    expect(sdp, isNot(contains('telephone-event')));
    expect(sdp, contains('a=rtpmap:8 PCMA/8000'));
    expect(sdp, contains('a=sendonly'));
  });

  test('voix vers la caméra : types statiques décrits même sans rtpmap', () {
    final sdp = onlyG711('v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111 0 8\r\na=rtpmap:111 opus/48000/2\r\n');
    expect(sdp, contains('a=rtpmap:8 PCMA/8000'));
    expect(sdp, contains('a=rtpmap:0 PCMU/8000'));
  });
}
