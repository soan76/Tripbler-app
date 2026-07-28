import 'package:flutter/material.dart';

// 번역 화면을 구성하는 StatelessWidget - 전체 수정 예정
class TranslationScreen extends StatelessWidget {
  const TranslationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFFC5E1A5),
      child: const Center(
        child: Text(
          '번역 화면',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}
