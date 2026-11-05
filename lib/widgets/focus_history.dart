import 'package:flutter/widgets.dart';

/// 초점이 글 입력칸에 있는지. 입력칸에 초점을 둔 채 카드를 넘기거나 다른 버튼을 터치하는
/// 경우 그대로 두어야 하므로, 초점을 풀기 전에 이 값으로 가른다.
bool get primaryFocusInTextField =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

/// 지금 초점을 풀고 초점 기록을 비운다. 전에 쓴 입력칸이 기록에 남아 있으면, 나중에 초점이
/// 갈 곳을 잃을 때 그 입력칸으로 돌아가 키보드가 뜨고 화면이 올라간다.
/// 초점이 스코프 자체에 있으면 기록이 이미 비어 있다. 이때 풀면 상위 스코프(이전 화면들)의
/// 기록을 지우게 되므로 건너뛴다.
void releaseFocusHistory() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary != null && primary is! FocusScopeNode) primary.unfocus();
}
