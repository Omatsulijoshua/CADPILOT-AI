class AiPlanQuestion {
  const AiPlanQuestion({required this.id, required this.label, required this.question, required this.required, required this.suggestedValue});
  final String id;
  final String label;
  final String question;
  final bool required;
  final String suggestedValue;

  factory AiPlanQuestion.fromMap(Map<String, Object?> map) => AiPlanQuestion(
    id: map['id']! as String, label: map['label']! as String,
    question: map['question']! as String, required: map['required']! as bool,
    suggestedValue: map['suggestedValue']! as String,
  );
}

class AiPlanOption {
  const AiPlanOption({required this.id, required this.title, required this.description, required this.stages, required this.assumptions, required this.executableNow, required this.preparation});
  final String id;
  final String title;
  final String description;
  final List<String> stages;
  final List<String> assumptions;
  final bool executableNow;
  final List<String> preparation;

  factory AiPlanOption.fromMap(Map<String, Object?> map) => AiPlanOption(
    id: map['id']! as String, title: map['title']! as String,
    description: map['description']! as String,
    stages: List<String>.from(map['stages']! as List),
    assumptions: List<String>.from(map['assumptions']! as List),
    executableNow: map['executableNow']! as bool,
    preparation: List<String>.from(map['preparation']! as List),
  );
}

class AiDesignPlan {
  const AiDesignPlan({required this.raw, required this.planId, required this.summary, required this.objectType, required this.style, required this.questions, required this.options, required this.canUseDefaults});
  final Map<String, Object?> raw;
  final String planId;
  final String summary;
  final String objectType;
  final String? style;
  final List<AiPlanQuestion> questions;
  final List<AiPlanOption> options;
  final bool canUseDefaults;

  factory AiDesignPlan.fromMap(Map<String, Object?> map) {
    final extracted = Map<String, Object?>.from(map['extracted']! as Map);
    return AiDesignPlan(
      raw: map, planId: map['planId']! as String, summary: map['summary']! as String,
      objectType: extracted['objectType']! as String, style: extracted['style'] as String?,
      questions: (map['missingInputs']! as List).map((value) => AiPlanQuestion.fromMap(Map<String, Object?>.from(value as Map))).toList(growable: false),
      options: (map['options']! as List).map((value) => AiPlanOption.fromMap(Map<String, Object?>.from(value as Map))).toList(growable: false),
      canUseDefaults: map['canUseDefaults']! as bool,
    );
  }
}

class AiPlanResponse {
  const AiPlanResponse(this.plan, this.totalTokens);
  final AiDesignPlan plan;
  final int totalTokens;
}
