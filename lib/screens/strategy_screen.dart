import 'package:flutter/material.dart';

import '../services/alert_polling_config_service.dart';
import '../services/alert_polling_service.dart';
import '../theme/app_theme.dart';

class StrategyScreen extends StatefulWidget {
  const StrategyScreen({super.key});

  @override
  State<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends State<StrategyScreen> {
  AlertPollingConfig _alertConfig = AlertPollingConfig.defaultConfig;
  bool _loadingAlertConfig = true;

  @override
  void initState() {
    super.initState();
    _loadAlertConfig();
  }

  Future<void> _loadAlertConfig() async {
    final config = await AlertPollingConfigService().load();
    if (!mounted) return;
    setState(() {
      _alertConfig = config;
      _loadingAlertConfig = false;
    });
  }

  Future<void> _saveAlertConfig(AlertPollingConfig config) async {
    setState(() => _alertConfig = config);
    await AlertPollingConfigService().save(config);
    await AlertPollingService().refreshConfig();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('价格提醒轮询设置已保存')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('策略')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          const _HeaderCard(),
          const SizedBox(height: 16),
          _AlertPollingSettingsCard(
            config: _alertConfig,
            loading: _loadingAlertConfig,
            onChanged: _saveAlertConfig,
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: '名词解释'),
          const SizedBox(height: 10),
          const _TermCard(
            terms: [
              _Term(
                name: '播种',
                description: '把计划资金拆成多笔，按预设价格分批配置，而不是一次性满仓。',
              ),
              _Term(
                name: '种子股',
                description: '本金已经回收后仍保留下来的股票，账面成本趋近于零，但价格风险仍然存在。',
              ),
              _Term(
                name: '基金份额',
                description: '持有基金的数量单位，配置时按净值折算份额，回收时按份额和确认净值计算现金回笼金额。',
              ),
              _Term(
                name: '基金净值',
                description: '基金每份资产对应的价格，开放式基金通常按确认净值进行账务折算。',
              ),
              _Term(
                name: '份额回收',
                description: '记录基金份额减少并取回资金，实际到账金额取决于回收份额、确认净值和相关费用。',
              ),
              _Term(
                name: '回本',
                description: '记录股票或基金的一部分仓位回收，把最初投入的本金收回来，不等同于全部退出。',
              ),
              _Term(
                name: '仓位',
                description: '某只股票、基金或整个权益资产占总资金的比例，用来控制风险暴露。',
              ),
              _Term(
                name: '批次',
                description: '一次播种形成一条独立记录，包含价格/净值、数量/份额、手续费和日期。',
              ),
              _Term(
                name: '摊低成本',
                description: '价格或净值下行后按计划继续配置，使平均持仓成本下降；前提是标的长期逻辑没有恶化。',
              ),
              _Term(
                name: '退出红线',
                description: '一旦出现就停止加仓或清仓处理的条件，例如财务造假、退市风险、逻辑证伪。',
              ),
              _Term(
                name: '零成本进度',
                description: '已回收资金除以总投入成本，用来衡量本金回收完成度。',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: '核心框架'),
          const SizedBox(height: 10),
          const _FlowStep(
            index: '1',
            title: '选种',
            description: '股票看公司质量，基金看指数/策略、管理人、费率和长期有效性。',
            items: ['标的长期有效', '规则能看懂', '费用可接受', '估值进入可接受区间'],
          ),
          const _FlowStep(
            index: '2',
            title: '播种',
            description: '把计划资金拆成多批，按价格区间播下去，让配置动作服从事前计划。',
            items: ['单股仓位封顶', '首批轻仓试错', '每批间距足够大', '不因为涨跌临时追单'],
          ),
          const _FlowStep(
            index: '3',
            title: '回本',
            description: '达到预设回收条件后记录一部分现金回笼，优先把本金收回来，而不是追求最高点。',
            items: ['回收本金优先于扩大仓位', '回本后剩余资产单独标记', '不把浮盈作为确定收益', '税费和手续费计入成本'],
          ),
          const _FlowStep(
            index: '4',
            title: '留种',
            description: '本金回笼后，剩余股份或份额成为零成本仓位，后续重点是跟踪标的质量和退出条件。',
            items: ['股票观察基本面', '基金观察策略漂移', '分红记录入账', '避免为了零成本标签死扛'],
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: '播种前检查'),
          const SizedBox(height: 10),
          const _ChecklistCard(
            items: [
              '这家公司三年后仍可能存在且有竞争力。',
              '这只基金跟踪的指数或投资策略长期逻辑仍然成立。',
              '当前估值不是明显透支未来的价格。',
              '最坏情况下继续下跌 30%-50% 仍有资金和心理承受力。',
              '已经写好每一批播种价、配置金额和停止播种条件。',
              '已经写好回收本金的触发价和回收数量。',
            ],
          ),
          const SizedBox(height: 16),
          const _SectionTitle(title: '退出红线'),
          const SizedBox(height: 10),
          const _WarningCard(),
        ],
      ),
    );
  }
}

class _AlertPollingSettingsCard extends StatelessWidget {
  final AlertPollingConfig config;
  final bool loading;
  final ValueChanged<AlertPollingConfig> onChanged;

  const _AlertPollingSettingsCard({
    required this.config,
    required this.loading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const intervals = [1, 3, 5, 10, 15, 30, 60];
    final activeInterval =
        intervals.contains(config.intervalMinutes) ? config.intervalMinutes : 3;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: AppTheme.accentGold, size: 20),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  '价格提醒轮询',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: config.enabled,
                onChanged: loading
                    ? null
                    : (value) => onChanged(config.copyWith(enabled: value)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            config.enabled
                ? '周一至周五 ${config.startText}-${config.endText} · 每 ${config.intervalMinutes} 分钟'
                : '已关闭全局轮询',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: activeInterval,
            decoration: const InputDecoration(labelText: '轮询间隔'),
            dropdownColor: AppTheme.bgCardLight,
            items: intervals
                .map(
                  (minutes) => DropdownMenuItem<int>(
                    value: minutes,
                    child: Text('$minutes 分钟'),
                  ),
                )
                .toList(),
            onChanged: loading
                ? null
                : (value) {
                    if (value == null) return;
                    onChanged(config.copyWith(intervalMinutes: value));
                  },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimeButton(
                  label: '开始',
                  value: config.startText,
                  onTap: loading
                      ? null
                      : () => _pickTime(
                            context,
                            initialMinutes: config.startMinutes,
                            onPicked: (minutes) => onChanged(
                              config.copyWith(startMinutes: minutes),
                            ),
                          ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeButton(
                  label: '结束',
                  value: config.endText,
                  onTap: loading
                      ? null
                      : () => _pickTime(
                            context,
                            initialMinutes: config.endMinutes,
                            onPicked: (minutes) => onChanged(
                              config.copyWith(endMinutes: minutes),
                            ),
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(
    BuildContext context, {
    required int initialMinutes,
    required ValueChanged<int> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: initialMinutes ~/ 60,
        minute: initialMinutes % 60,
      ),
    );
    if (picked == null) return;
    onPicked(picked.hour * 60 + picked.minute);
  }
}

class _TimeButton extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.bgCardLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor, width: 0.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: AppTheme.textMuted, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TermCard extends StatelessWidget {
  final List<_Term> terms;

  const _TermCard({required this.terms});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        children: terms
            .map((term) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          term.name,
                          style: const TextStyle(
                            color: AppTheme.accentGold,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          term.description,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Term {
  final String name;
  final String description;

  const _Term({required this.name, required this.description});
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryGreen.withValues(alpha: 0.12),
            AppTheme.accent.withValues(alpha: 0.13),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.28)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '零成本资产播种术',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '本 App 把股票和基金自持拆成四件事：选种、播种、回本、留种。它只做计划、计算和记录，行情数据来自合规金融数据服务商，不提供标的推荐或代客管理。',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _FlowStep extends StatelessWidget {
  final String index;
  final String title;
  final String description;
  final List<String> items;

  const _FlowStep({
    required this.index,
    required this.title,
    required this.description,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  index,
                  style: const TextStyle(
                      color: AppTheme.accent, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) => _Pill(text: item)).toList(),
          ),
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  final List<String> items;

  const _ChecklistCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Column(
        children: items
            .map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_box_outline_blank,
                          size: 17, color: AppTheme.textMuted),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          item,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard();

  @override
  Widget build(BuildContext context) {
    const warnings = [
      '公司基本面被证伪，不能继续用价格下跌解释风险。',
      '基金出现严重策略漂移、长期大幅跑输基准或费率不再合理。',
      '财务造假、退市、重大诉讼、核心资产丧失等不可逆事件出现。',
      '为了摊低成本不断加仓，实际仓位已经超过原计划上限。',
      '回收本金条件已满足却反复贪心，导致计划失去纪律。',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.riskRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: warnings
            .map((warning) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.report_gmailerrorred,
                          color: AppTheme.riskRed, size: 18),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          warning,
                          style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                              height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgCardLight,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.borderColor, width: 0.5),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
