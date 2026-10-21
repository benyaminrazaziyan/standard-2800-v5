import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const SeismoApp());

class SeismoApp extends StatelessWidget {
  const SeismoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Standard 2800-V5', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF164E63)), useMaterial3: true),
    home: const CalculatorPage(),
  );
}

/// Equations currently reproduce the supplied Excel workbook, not a substitute for
/// checking the complete official Standard 2800 fifth edition and its corrigenda.
class Results {
  final double h, ie, ru, ss, s1, fs, f1, ta, te, t, sms, sm1, sds, sd1, t0, ts, tl, sa, cmin, cRaw, c, k;
  final String seismicGroup;
  final int? sdc;
  const Results({required this.h, required this.ie, required this.ru, required this.ss, required this.s1,
    required this.fs, required this.f1, required this.ta, required this.te, required this.t,
    required this.sms, required this.sm1, required this.sds, required this.sd1, required this.t0,
    required this.ts, required this.tl, required this.sa, required this.cmin, required this.cRaw, required this.c,
    required this.k, required this.seismicGroup, required this.sdc});
}

Results calculate({required double h, required double ie, required int system, required double ru,
  required double ss, required double s1, required double fs, required double f1, required double ta}) {
  if ([h, ie, ru, ss, s1, fs, f1, ta].any((x) => !x.isFinite || x <= 0)) {
    throw ArgumentError('تمام ورودی‌ها باید عددی و بزرگ‌تر از صفر باشند.');
  }
  late double te;
  switch (system) {
    case 1: te = (0.072 * math.pow(h, 0.8)).toDouble(); break;
    case 2: te = (0.047 * math.pow(h, 0.9)).toDouble(); break;
    case 3: te = (0.049 * math.pow(h, 0.75)).toDouble(); break;
    case 4: te = (0.073 * math.pow(h, 0.75)).toDouble(); break;
    case 5: case 6: te = (0.049 * math.pow(h, 0.75)).toDouble(); break;
    default: throw ArgumentError('سیستم سازه‌ای نامعتبر است.');
  }
  final sms = ss * fs, sm1 = s1 * f1;
  final sds = (2 / 3) * sms, sd1 = (2 / 3) * sm1;
  if ([te, sms, sm1, sds, sd1].any((x) => !x.isFinite || x <= 0)) {
    throw ArgumentError('نتیجه میانی نامعتبر است؛ بزرگی ورودی‌ها و ضرایب را کنترل کنید.');
  }
  final t0 = 0.2 * (sd1 / sds), ts = sd1 / sds, tl = 6.0;
  final t = math.min(1.4 * te, ta).toDouble();
  final sa = spectrumAt(t, sds, sd1, t0, ts, tl);
  if ([t0, ts, t, sa].any((x) => !x.isFinite) || t0 <= 0 || ts <= 0 || t <= 0 || sa <= 0) {
    throw ArgumentError('محاسبات طیف به نتیجه عددی معتبر نرسید؛ ورودی‌ها را کنترل کنید.');
  }
  // Standard 2800 fifth edition, clauses 3-9-3-2-1 and equations 3-3 to 3-5:
  // the baseline minimum coefficient always applies; S1 >= 0.6 adds a second lower bound.
  final cminBase = math.max(0.044 * sds * ie, 0.01).toDouble();
  final cmin = (s1 >= 0.6
      ? math.max(cminBase, 0.5 * s1 / (ru / ie))
      : cminBase).toDouble();
  final cRaw = (sa / (ru / ie)).toDouble();
  // Effective coefficient for the simplified base-shear calculation after minimum-base-shear check.
  final c = math.max(cmin, cRaw).toDouble();
  final k = (t < 0.5 ? 1.0 : t > 2.5 ? 2.0 : 0.5 * t + 0.75).toDouble();
  final group = ie * sd1 <= 0.4 && ie * sds <= 0.75 ? 'A'
      : (ie * s1 <= 0.6 && (ie * sd1 > 0.4 || ie * sds > 0.75)) ? 'B'
      : ie * s1 > 0.6 ? 'C' : 'نامشخص';
  return Results(h: h, ie: ie, ru: ru, ss: ss, s1: s1, fs: fs, f1: f1, ta: ta,
    te: te, t: t, sms: sms, sm1: sm1, sds: sds, sd1: sd1, t0: t0, ts: ts, tl: tl,
    sa: sa, cmin: cmin, cRaw: cRaw, c: c, k: k, seismicGroup: group, sdc: _sdcFor(group, ie));
}

class HeightLimitSystem {
  final String id, label;
  final double ru;
  final List<double?> hmBySdc; // SDC-1, SDC-2, SDC-3; null means prohibited in the table
  const HeightLimitSystem(this.id, this.label, this.ru, this.hmBySdc);
}

/// Transcribed from Standard 2800 fifth-edition Table 1-3.
/// Heights are ordered SDC-1, SDC-2, SDC-3. Special footnotes/exceptions
/// are not automatically adjudicated by this basic height comparison.
const heightLimitSystems = <HeightLimitSystem>[
  // A — Bearing-wall systems
  HeightLimitSystem('bearing_coupled_ductile_rc_wall', 'دیوار برشی بتن‌آرمه همبند شکل‌پذیر [یادداشت ۱]', 6.5, [50, 50, 50]),
  HeightLimitSystem('bearing_special_rc_wall', 'دیوار برشی بتن‌آرمه ویژه', 5.0, [50, 50, 50]),
  HeightLimitSystem('bearing_ordinary_rc_wall', 'دیوار برشی بتن‌آرمه معمولی [یادداشت ۲]', 4.0, [15, 10.5, null]),
  HeightLimitSystem('bearing_reinforced_masonry_wall', 'دیوار برشی بنایی مسلح', 4.0, [15, 10.5, 10.5]),
  HeightLimitSystem('bearing_cfs_strap_wall', 'دیوار قاب سبک فولادی سردنورد با مهار تسمه‌ای', 4.0, [20, 15, 10.5]),
  HeightLimitSystem('bearing_cfs_sheathed_wall', 'دیوار قاب سبک فولادی سردنورد با پوشش فولادی یا چوبی', 5.5, [20, 15, 10.5]),
  HeightLimitSystem('bearing_3d_shotcrete_wall', 'دیوار بتن پاششی سه‌بعدی', 3.0, [15, 10.5, null]),
  // B — Building-frame systems
  HeightLimitSystem('frame_coupled_ductile_rc_wall', 'قاب ساختمانی + دیوار برشی بتن‌آرمه همبند شکل‌پذیر [یادداشت‌های ۱ و ۳]', 6.5, [50, 50, 50]),
  HeightLimitSystem('frame_special_rc_wall', 'قاب ساختمانی + دیوار برشی بتن‌آرمه ویژه [یادداشت ۳]', 6.0, [50, 50, 50]),
  HeightLimitSystem('frame_ordinary_rc_wall', 'قاب ساختمانی + دیوار برشی بتن‌آرمه معمولی [یادداشت ۲]', 4.5, [15, 10.5, null]),
  HeightLimitSystem('frame_reinforced_masonry_wall', 'قاب ساختمانی + دیوار برشی بنایی مسلح', 4.0, [15, 10.5, 10.5]),
  HeightLimitSystem('frame_special_steel_scbraced', 'قاب مهاربندی همگرای فولادی ویژه [یادداشت ۳]', 6.0, [50, 50, 50]),
  HeightLimitSystem('frame_ordinary_steel_scbraced', 'قاب مهاربندی همگرای فولادی معمولی', 3.5, [15, 10.5, null]),
  HeightLimitSystem('frame_steel_ebf_shear_link', 'قاب مهاربندی واگرای فولادی با تیر پیوند برشی [یادداشت ۳]', 6.5, [50, 50, 50]),
  HeightLimitSystem('frame_steel_ebf_flexural_link', 'قاب مهاربندی واگرای فولادی با تیر پیوند خمشی یا خمشی‌ـ‌برشی', 6.0, [50, 50, 40]),
  HeightLimitSystem('frame_steel_brbf', 'قاب مهاربندی کمانش‌تاب [یادداشت ۳]', 6.5, [50, 50, 50]),
  HeightLimitSystem('frame_special_steel_shear_wall', 'دیوار برشی فولادی ویژه', 6.0, [50, 50, 50]),
  HeightLimitSystem('frame_special_composite_scbraced', 'قاب مهاربندی همگرای مختلط ویژه', 5.0, [50, 50, 50]),
  HeightLimitSystem('frame_special_composite_ebf', 'قاب مهاربندی واگرای مختلط ویژه', 6.5, [50, 50, 50]),
  HeightLimitSystem('frame_special_composite_shear_wall', 'دیوار برشی مختلط ویژه', 5.5, [50, 50, 50]),
  // C — Moment-frame systems
  HeightLimitSystem('moment_special_rc', 'قاب خمشی بتن‌آرمه ویژه', 6.5, [100, 70, 50]),
  HeightLimitSystem('moment_intermediate_rc', 'قاب خمشی بتن‌آرمه متوسط [یادداشت‌های ۴ و ۵]', 4.5, [21, 18, null]),
  HeightLimitSystem('moment_ordinary_rc', 'قاب خمشی بتن‌آرمه معمولی [یادداشت ۵]', 3.0, [10.5, null, null]),
  HeightLimitSystem('moment_special_steel', 'قاب خمشی فولادی ویژه', 6.5, [120, 100, 80]),
  HeightLimitSystem('moment_intermediate_steel', 'قاب خمشی فولادی متوسط [یادداشت ۶]', 4.5, [28, 21, null]),
  HeightLimitSystem('moment_ordinary_steel', 'قاب خمشی فولادی معمولی [یادداشت ۷]', 3.5, [10.5, null, null]),
  HeightLimitSystem('moment_special_steel_truss', 'قاب خمشی خرپایی فولادی ویژه', 6.0, [50, 35, 35]),
  HeightLimitSystem('moment_special_composite', 'قاب خمشی مختلط ویژه', 6.5, [120, 100, 70]),
  // D — Dual systems
  HeightLimitSystem('dual_special_moment_coupled_ductile_rc_wall', 'دوگانه: قاب خمشی ویژه + دیوار بتن‌آرمه همبند شکل‌پذیر [یادداشت ۱]', 7.5, [200, 200, 200]),
  HeightLimitSystem('dual_special_moment_special_rc_wall', 'دوگانه: قاب خمشی ویژه + دیوار برشی بتن‌آرمه ویژه', 7.0, [200, 200, 200]),
  HeightLimitSystem('dual_special_steel_moment_special_scbrace', 'دوگانه: قاب خمشی فولادی ویژه + مهاربند همگرای فولادی ویژه', 7.0, [200, 200, 200]),
  HeightLimitSystem('dual_special_steel_moment_ebf_shear', 'دوگانه: قاب خمشی فولادی ویژه + مهاربند واگرای با پیوند برشی', 7.5, [200, 200, 200]),
  HeightLimitSystem('dual_special_steel_moment_ebf_flexural', 'دوگانه: قاب خمشی فولادی ویژه + مهاربند واگرای با پیوند خمشی یا مختلط', 7.0, [200, 200, 200]),
  HeightLimitSystem('dual_special_steel_moment_brbf', 'دوگانه: قاب خمشی فولادی ویژه + مهاربند کمانش‌تاب', 7.0, [200, 200, 200]),
  HeightLimitSystem('dual_special_steel_moment_shearwall', 'دوگانه: قاب خمشی فولادی ویژه + دیوار برشی فولادی ویژه', 7.0, [200, 200, 200]),
  HeightLimitSystem('dual_intermediate_moment_special_rc_wall', 'دوگانه: قاب خمشی متوسط + دیوار برشی بتن‌آرمه ویژه', 6.0, [50, 35, 21]),
  HeightLimitSystem('dual_intermediate_steel_moment_special_scbrace', 'دوگانه: قاب خمشی فولادی متوسط + مهاربند همگرای فولادی ویژه', 6.0, [50, 35, 21]),
  HeightLimitSystem('dual_special_moment_special_composite_scbrace', 'دوگانه: قاب خمشی ویژه + مهاربند همگرای مختلط ویژه', 6.0, [200, 200, 200]),
  HeightLimitSystem('dual_special_moment_special_composite_ebf', 'دوگانه: قاب خمشی ویژه + مهاربند واگرای مختلط', 7.5, [200, 200, 200]),
  HeightLimitSystem('dual_special_moment_special_composite_wall', 'دوگانه: قاب خمشی ویژه + دیوار برشی مختلط ویژه', 7.0, [200, 200, 200]),
  HeightLimitSystem('dual_intermediate_moment_special_composite_scbrace', 'دوگانه: قاب خمشی متوسط + مهاربند همگرای مختلط ویژه', 5.0, [35, 28, 15]),
  // E — Cantilever column system
  HeightLimitSystem('cantilever_special_steel_or_rc_column', 'سیستم ستون کنسولی فولادی یا بتن‌آرمه ویژه', 2.0, [10.5, 10.5, 10.5]),
];

class HeightLimitResult {
  final double? hm;
  final bool permitted;
  final String message;
  const HeightLimitResult(this.hm, this.permitted, this.message);
}

HeightLimitResult checkHeightLimit({required String systemId, required int sdc, required double height}) {
  if (sdc < 1 || sdc > 3 || !height.isFinite || height <= 0) {
    throw ArgumentError('گروه طراحی لرزه‌ای و ارتفاع باید معتبر باشند.');
  }
  final matches = heightLimitSystems.where((x) => x.id == systemId);
  if (matches.isEmpty) throw ArgumentError('سیستم انتخاب‌شده در فهرست کنترل محدودیت ارتفاع وجود ندارد.');
  final selected = matches.first;
  final hm = selected.hmBySdc[sdc - 1];
  if (hm == null) {
    if (selected.id == 'moment_intermediate_steel' && sdc == 3) {
      return const HeightLimitResult(null, false, 'ردیف جدول ۱-۳ غیرمجاز نشان می‌دهد؛ یادداشت ۶ فقط در شرایط ویژه ساختمان یک‌طبقه و محدودیت بارها، ارتفاع تا ۱۵ متر را مجاز می‌داند. این شرایط در برنامه کنترل نمی‌شوند و بررسی دستی الزامی است.');
    }
    if (selected.id == 'moment_ordinary_steel' && sdc <= 2) {
      return const HeightLimitResult(null, false, 'ردیف جدول ۱-۳ غیرمجاز نشان می‌دهد؛ یادداشت ۷ فقط در شرایط ویژه ساختمان یک‌طبقه و محدودیت بارها، ارتفاع تا ۲۰ متر را مجاز می‌داند. این شرایط در برنامه کنترل نمی‌شوند و بررسی دستی الزامی است.');
    }
    return const HeightLimitResult(null, false, 'این ردیف جدول ۱-۳ برای گروه طراحی لرزه‌ای انتخاب‌شده غیرمجاز درج شده است؛ یادداشت‌ها و استثناهای مربوط باید در متن استاندارد بررسی شوند.');
  }
  if (height > hm) {
    final note3Applies = <String>{'frame_coupled_ductile_rc_wall','frame_special_rc_wall','frame_special_steel_scbraced','frame_steel_ebf_shear_link','frame_steel_brbf'}.contains(selected.id) && height <= 70 && sdc != 3;
    return HeightLimitResult(hm, false, note3Applies
      ? 'ارتفاع از حد پایه ۵۰ متر بیشتر است. یادداشت ۳ امکان افزایش مشروط تا ۷۰ متر را فقط با تحقق هم‌زمان شروط آیین‌نامه مطرح می‌کند؛ برنامه این شروط را کنترل نمی‌کند.'
      : 'ارتفاع از حد عددی ردیف جدول ۱-۳ بیشتر است؛ استثناها و یادداشت‌های مشروط جدول باید جداگانه بررسی شوند.');
  }
  final notes = <String>[];
  if (selected.id == 'bearing_coupled_ductile_rc_wall' ||
      selected.id == 'frame_coupled_ductile_rc_wall' ||
      selected.id == 'dual_special_moment_coupled_ductile_rc_wall') {
    notes.add('یادداشت ۱: اگر سیستم مشمول این یادداشت باشد و ارتفاع از تراز پایه کمتر از ۱۸ متر باشد، پارامترهای لرزه‌ای دیوار باید طبق متن استاندارد بررسی شوند.');
  }
  if ((selected.id == 'bearing_ordinary_rc_wall' || selected.id == 'frame_ordinary_rc_wall') && sdc == 2) {
    notes.add('یادداشت ۲: استفاده از دیوار برشی بتن‌آرمه معمولی در گروه ۲ مشروط به نبود بازشو، طول کافی دیوار و محدودیت تنش قائم است؛ این شروط خودکار کنترل نمی‌شوند.');
  }
  if (<String>{'frame_coupled_ductile_rc_wall','frame_special_rc_wall','frame_special_steel_scbraced','frame_steel_ebf_shear_link','frame_steel_brbf'}.contains(selected.id)) {
    notes.add('یادداشت ۳: اگر ارتفاع بیش از ۵۰ متر مدنظر باشد، افزایش تا ۷۰ متر فقط با تحقق هم‌زمان شروط یادداشت ۳ مجاز است؛ برنامه نامنظمی پیچشی شدید و سهم برش قاب‌ها را بررسی نمی‌کند.');
  }
  if (selected.id == 'moment_intermediate_rc' && sdc == 2) {
    notes.add('یادداشت ۴: استفاده از قاب خمشی بتن‌آرمه متوسط در گروه ۲ نیازمند رعایت ضوابط جزئیات و کنترل ظرفیت خمشی ستون‌ها نسبت به تیرهاست.');
  }
  if (selected.id == 'moment_intermediate_rc' || selected.id == 'moment_ordinary_rc') {
    notes.add('یادداشت ۵: حداقل ابعاد ستون و محدودیت فاصله تنگ‌ها باید جداگانه کنترل شوند.');
  }
  final baseMessage = 'ارتفاع از حد عددی ردیف جدول بیشتر نیست؛ این نتیجه فقط کنترل عددی ارتفاع است و به معنی تأیید کامل انطباق آیین‌نامه‌ای نیست.';
  return HeightLimitResult(hm, true, notes.isEmpty ? '$baseMessage یادداشت‌های جدول، نوع سیستم در هر امتداد و تأیید مهندس مسئول همچنان باید جداگانه بررسی شوند.' : '$baseMessage\n${notes.join('\n')}');
}

class SiteFactors {
  final double fs, f1;
  const SiteFactors(this.fs, this.f1);
}

/// Linear interpolation of Standard 2800 fifth-edition Tables 1-2 and 2-2.
/// Soil type VI requires a site-specific spectrum and is intentionally rejected.
SiteFactors siteFactors({required int soilType, required double ss, required double s1}) {
  if (soilType < 1 || soilType > 6 || !ss.isFinite || !s1.isFinite || ss < 0.5 || s1 < 0.2) {
    throw ArgumentError('نوع زمین باید I تا VI باشد؛ برای درون‌یابی جدول، Ss باید حداقل 0.5 و S1 حداقل 0.2 باشد.');
  }
  if (soilType == 6) {
    throw ArgumentError('برای زمین نوع VI، طیف ویژه ساختگاه لازم است؛ ضرایب Fs و F1 از این جدول به‌تنهایی تعیین نمی‌شوند.');
  }
  const ssKnots = <double>[0.5, 0.75, 1.0, 1.25, 1.5];
  const fsRows = <int, List<double>>{
    1: [1.0, 1.0, 1.0, 1.0, 1.0],
    2: [1.2, 1.2, 1.1, 1.0, 1.0],
    3: [1.3, 1.2, 1.1, 1.0, 1.0],
    4: [1.6, 1.3, 1.3, 1.1, 1.1],
    5: [1.6, 1.4, 1.4, 1.2, 1.2],
  };
  const s1Knots = <double>[0.2, 0.3, 0.4, 0.5, 0.6];
  const f1Rows = <int, List<double>>{
    1: [1.0, 1.0, 1.0, 1.0, 1.0],
    2: [1.5, 1.3, 1.3, 1.3, 1.3],
    3: [2.2, 2.1, 2.1, 2.1, 2.1],
    4: [3.3, 3.3, 3.2, 2.8, 2.8],
    5: [2.2, 2.1, 2.1, 2.1, 2.1],
  };
  double interpolate(double x, List<double> knots, List<double> values) {
    if (x >= knots.last) return values.last;
    for (var i = 0; i < knots.length - 1; i++) {
      if (x <= knots[i + 1]) {
        final ratio = (x - knots[i]) / (knots[i + 1] - knots[i]);
        return values[i] + ratio * (values[i + 1] - values[i]);
      }
    }
    return values.last;
  }
  return SiteFactors(
    interpolate(ss, ssKnots, fsRows[soilType]!),
    interpolate(s1, s1Knots, f1Rows[soilType]!),
  );
}

double spectrumAt(double t, double sds, double sd1, double t0, double ts, double tl) {
  if ([t, sds, sd1, t0, ts, tl].any((x) => !x.isFinite) || t < 0 || sds <= 0 || sd1 <= 0 || t0 <= 0 || ts <= 0 || tl <= 0) {
    throw ArgumentError('پارامترهای طیف باید مثبت باشند.');
  }
  if (t <= t0) return sds * (0.4 + 0.6 * t / t0);
  if (t <= ts) return sds;
  if (t < tl) return sd1 / t;
  return sd1 * tl / (t * t);
}

int? _sdcFor(String group, double ie) {
  final col = (ie - 0.8).abs() < 1e-9 ? 0 : (ie - 1.0).abs() < 1e-9 ? 1 : (ie - 1.2).abs() < 1e-9 ? 2 : (ie - 1.4).abs() < 1e-9 ? 3 : -1;
  if (col < 0) return null;
  const values = <String, List<int>>{'A': [1, 1, 2, 3], 'B': [2, 2, 2, 3], 'C': [3, 3, 3, 3]};
  final row = values[group];
  return row == null ? null : row[col];
}

class FloorForce { final int floor; final double height, weight, factor, force; const FloorForce(this.floor, this.height, this.weight, this.factor, this.force); }
List<FloorForce> distributeBaseShear({required List<double> heights, required List<double> weights, required double baseShear, required double k}) {
  if (heights.isEmpty || heights.length != weights.length || !baseShear.isFinite || baseShear < 0 || !k.isFinite || k <= 0) throw ArgumentError('ورودی‌های توزیع نیروی طبقات معتبر نیستند.');
  for (var i=0; i<heights.length; i++) { if (!heights[i].isFinite || heights[i] <= 0 || !weights[i].isFinite || weights[i] <= 0 || (i>0 && heights[i] <= heights[i-1])) throw ArgumentError('ارتفاع‌ها باید صعودی و همه وزن‌ها و ارتفاع‌ها مثبت باشند.'); }
  final terms = List<double>.generate(heights.length, (i) => weights[i] * math.pow(heights[i], k));
  if (terms.any((x) => !x.isFinite || x <= 0)) throw ArgumentError('حاصل Wi·hi^K خارج از محدوده عددی معتبر است.');
  final sum = terms.fold<double>(0, (a,b)=>a+b);
  if (!sum.isFinite || sum <= 0) throw ArgumentError('مجموع وزن‌های تعدیل‌شده معتبر نیست.');
  final forces = List<FloorForce>.generate(heights.length, (i) => FloorForce(i+1, heights[i], weights[i], terms[i], baseShear*terms[i]/sum));
  if (forces.any((f) => !f.force.isFinite)) throw ArgumentError('نیروی محاسبه‌شده طبقه خارج از محدوده عددی معتبر است.');
  return forces;
}

class CalculatorPage extends StatefulWidget { const CalculatorPage({super.key}); @override State<CalculatorPage> createState() => _CalculatorPageState(); }
class _CalculatorPageState extends State<CalculatorPage> {
  final _form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{
    'h': TextEditingController(text: '15'), 'ie': TextEditingController(text: '1'),
    'ru': TextEditingController(text: '6.5'), 'ss': TextEditingController(text: '1.4'),
    's1': TextEditingController(text: '0.6'), 'fs': TextEditingController(text: '1.0'),
    'f1': TextEditingController(text: '1.3'), 'ta': TextEditingController(text: '1.0'),
  };
  final floorCount = TextEditingController(text: '5');
  final floorHeight = TextEditingController(text: '3');
  final floorWeights = TextEditingController(text: '100; 100; 100; 100; 100');
  int system = 2, tab = 0, soilType = 2, heightSdc = 1;
  String heightSystemId = 'moment_special_rc';
  Results? result; String? error; List<FloorForce> forces = [];
  HeightLimitResult? heightCheck;
  double val(String key) => double.parse(fields[key]!.text.trim().replaceAll(',', '.'));
  @override void dispose() { for (final c in fields.values) { c.dispose(); } floorCount.dispose(); floorHeight.dispose(); floorWeights.dispose(); super.dispose(); }
  Widget input(String key, String label, String unit) => TextFormField(
    controller: fields[key], keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label, suffixText: unit, border: const OutlineInputBorder()),
    validator: (v) { final n = double.tryParse((v ?? '').trim().replaceAll(',', '.')); return n == null || !n.isFinite || n <= 0 ? 'عدد مثبت وارد کنید' : null; },
  );
  Widget metric(String label, double value, {String unit = ''}) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 6), Text('${value.toStringAsFixed(4)} $unit', style: Theme.of(context).textTheme.titleMedium)])));
  void applySiteFactors() {
    try {
      final factors = siteFactors(soilType: soilType, ss: val('ss'), s1: val('s1'));
      setState(() { fields['fs']!.text = factors.fs.toStringAsFixed(3); fields['f1']!.text = factors.f1.toStringAsFixed(3); error = null; });
    } catch (e) { setState(() => error = e.toString()); }
  }
  void runCalc() {
    if (!_form.currentState!.validate()) return;
    try {
      final r = calculate(h: val('h'), ie: val('ie'), system: system, ru: val('ru'), ss: val('ss'), s1: val('s1'), fs: val('fs'), f1: val('f1'), ta: val('ta'));
      setState(() {
        result = r;
        error = null;
        forces = [];
        heightCheck = null;
        // Keep the preliminary height check aligned with the SDC just calculated.
        // The user may still change this selector manually when reviewing a scenario.
        if (r.sdc != null) heightSdc = r.sdc!;
      });
    } catch (e) { setState(() => error = e.toString()); }
  }
  String report() { final r=result; if (r==null) return 'ابتدا محاسبه را انجام دهید.'; final b=StringBuffer('گزارش محاسبات لرزه‌ای - استاندارد ۲۸۰۰ ویرایش پنجم\n');
    b.writeln('ارتفاع H=${r.h} m | Ie=${r.ie} | Ru=${r.ru}'); b.writeln('Ss=${r.ss} g | S1=${r.s1} g | Fs=${r.fs} | F1=${r.f1}');
    b.writeln('Te=${r.te} s | T=${r.t} s | SMS=${r.sms} | SM1=${r.sm1} | SDS=${r.sds} | SD1=${r.sd1}');
    b.writeln('T0=${r.t0} s | Ts=${r.ts} s | TL=${r.tl} s | Sa(T)=${r.sa} g | C_raw=Sa/(Ru/Ie)=${r.cRaw} | Cmin=${r.cmin} | C_effective=max(C_raw,Cmin)=${r.c} | K=${r.k}');
    b.writeln('گروه لرزه‌ای=${r.seismicGroup} | SDC=${r.sdc ?? 'نامشخص'}');
    if (forces.isNotEmpty) { b.writeln('\nتوزیع نیروی جانبی (واحد وزن و نیرو مطابق ورودی):'); for(final f in forces) { b.writeln('طبقه ${f.floor}: h=${f.height}, W=${f.weight}, F=${f.force}'); } }
    b.writeln('\nمبنای روابط: تطبیق اولیه با استاندارد ۲۸۰۰ ویرایش پنجم و فایل اکسل مرجع. سایر الزامات آیین‌نامه هنوز به‌طور کامل پیاده‌سازی نشده‌اند؛ گزارش جایگزین بررسی مهندس مسئول نیست.'); return b.toString(); }
  void runDistribution() { final r=result; if(r==null){setState(()=>error='ابتدا پارامترهای لرزه‌ای را محاسبه کنید.');return;} try {
    final n=int.parse(floorCount.text.trim()); final dh=double.parse(floorHeight.text.trim().replaceAll(',','.')); final ws=floorWeights.text.split(RegExp(r'[;\s]+')).where((s)=>s.isNotEmpty).map((s)=>double.parse(s.replaceAll(',','.'))).toList();
    if(n<1||n>100||dh<=0||ws.length!=n) throw ArgumentError('تعداد وزن‌ها باید دقیقاً برابر تعداد طبقات باشد. وزن‌ها را با نقطه‌ویرگول یا فاصله جدا کنید؛ برای اعشار می‌توانید از نقطه یا ویرگول استفاده کنید.');
    final hs=List<double>.generate(n,(i)=>(i+1)*dh); final totalW=ws.fold<double>(0,(a,b)=>a+b); final base=r.c*totalW;
    setState(()=>forces=distributeBaseShear(heights:hs,weights:ws,baseShear:base,k:r.k));
  } catch(e){setState(()=>error='خطا در توزیع نیرو: $e');} }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Standard 2800-V5'), actions:[IconButton(tooltip:'کپی گزارش',onPressed: result==null?null:() async {await Clipboard.setData(ClipboardData(text:report())); if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('گزارش در حافظه موقت کپی شد.')));},icon:const Icon(Icons.copy_all))]),
    body: IndexedStack(index:tab,children:[_inputs(),_results(),_distribution(),_about()]),
    bottomNavigationBar: NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [NavigationDestination(icon:Icon(Icons.tune),label:'ورودی‌ها'),NavigationDestination(icon:Icon(Icons.show_chart),label:'نتایج و طیف'),NavigationDestination(icon:Icon(Icons.account_tree),label:'نیروی طبقات'),NavigationDestination(icon:Icon(Icons.menu_book),label:'راهنما')]),
  );
  Widget _inputs()=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('پارامترهای محاسبه',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('واحد شتاب Ss و S1 برابر g است. انتخاب رابطه زمان تناوب از فهرست اکسل ساده‌سازی شده است؛ سیستم واقعی مقاوم جانبی را جداگانه از جدول ۱-۳ انتخاب کنید. با انتخاب آن، Ru به مقدار جدول به‌روزرسانی می‌شود. کنترل کامل یادداشت‌ها و استثناهای آیین‌نامه همچنان لازم است.'),const SizedBox(height:16),
    Form(key:_form,child:Column(children:[input('h','ارتفاع سازه H','m'),const SizedBox(height:10),input('ie','ضریب اهمیت Ie',''),const SizedBox(height:10),
DropdownButtonFormField<int>(
  value: system,
  isExpanded: true,
  decoration: const InputDecoration(
    labelText: 'گزینه ساده‌شده برای رابطه زمان تناوب (طبق اکسل)',
    border: OutlineInputBorder(),
  ),items:const [
        DropdownMenuItem(value:1,child:Text('۱ ـ قاب خمشی فولادی/مختلط بدون میانقاب')),
        DropdownMenuItem(value:2,child:Text('۲ ـ قاب خمشی بتنی بدون میانقاب')),
        DropdownMenuItem(value:3,child:Text('۳ ـ سایر سیستم‌ها؛ رابطه تجربی ۰٫۰۴۹H^۰٫۷۵')),
        DropdownMenuItem(value:4,child:Text('۴ ـ قاب ساده/دوگانه با مهاربند واگرا یا کمانش‌تاب، بدون میانقاب')),
        DropdownMenuItem(value:5,child:Text('۵ ـ سیستم مهاربندی با اثر میانقاب؛ رابطه تجربی ۰٫۰۴۹H^۰٫۷۵')),
        DropdownMenuItem(value:6,child:Text('۶ ـ سایر سیستم‌ها (همان رابطه تجربی ۰٫۰۴۹H^۰٫۷۵)'))],onChanged:(v)=>setState(()=>system=v??2)),const SizedBox(height:10),input('ru','ضریب رفتار Ru (با انتخاب سیستم جدول ۱-۳ به‌روزرسانی می‌شود)',''),const SizedBox(height:10),
      Row(children:[Expanded(child:input('ss','Ss','g')),const SizedBox(width:10),Expanded(child:input('s1','S1','g'))]),const SizedBox(height:10),
      DropdownButtonFormField<int>(value:soilType,decoration:const InputDecoration(labelText:'نوع زمین طبق جدول ۵-۲',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:1,child:Text('نوع I')),DropdownMenuItem(value:2,child:Text('نوع II')),DropdownMenuItem(value:3,child:Text('نوع III')),DropdownMenuItem(value:4,child:Text('نوع IV')),DropdownMenuItem(value:5,child:Text('نوع V')),DropdownMenuItem(value:6,child:Text('نوع VI — طیف ویژه'))],onChanged:(v)=>setState(()=>soilType=v??2)),const SizedBox(height:8),
      OutlinedButton.icon(onPressed:applySiteFactors,icon:const Icon(Icons.auto_fix_high),label:const Text('محاسبه Fs و F1 از جدول‌های ۱-۲ و ۲-۲')),const SizedBox(height:10),
      Row(children:[Expanded(child:input('fs','ضریب ساختگاه Fs','')),const SizedBox(width:10),Expanded(child:input('f1','ضریب ساختگاه F1',''))]),const SizedBox(height:10),input('ta','دوره تناوب تحلیلی واردشده از ETABS (Ta)','s'),const SizedBox(height:14),
      FilledButton.icon(onPressed:runCalc,icon:const Icon(Icons.calculate),label:const Text('محاسبه پارامترها'),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48))),
      const SizedBox(height:22), const Align(alignment:Alignment.centerRight,child:Text('کنترل محدودیت ارتفاع — جدول ۱-۳',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))), const SizedBox(height:8),
      DropdownButtonFormField<String>(value:heightSystemId,decoration:const InputDecoration(labelText:'سیستم مقاوم جانبی مطابق جدول ۱-۳',border:OutlineInputBorder()),isExpanded:true,items:heightLimitSystems.map((x)=>DropdownMenuItem(value:x.id,child:Text(x.label,overflow:TextOverflow.visible))).toList(),onChanged:(v){final id=v??heightSystemId; final selected=heightLimitSystems.firstWhere((x)=>x.id==id); setState((){heightSystemId=id; fields['ru']!.text=selected.ru.toString(); heightCheck=null;});}), const SizedBox(height:10),
      DropdownButtonFormField<int>(value:heightSdc,decoration:const InputDecoration(labelText:'گروه طراحی لرزه‌ای SDC',border:OutlineInputBorder()),items:const [DropdownMenuItem(value:1,child:Text('SDC-1')),DropdownMenuItem(value:2,child:Text('SDC-2')),DropdownMenuItem(value:3,child:Text('SDC-3'))],onChanged:(v)=>setState(()=>heightSdc=v??1)), const SizedBox(height:10),
      OutlinedButton.icon(onPressed:(){try{final r=checkHeightLimit(systemId:heightSystemId,sdc:heightSdc,height:val('h'));setState(()=>heightCheck=r);}catch(e){setState(()=>error=e.toString());}},icon:const Icon(Icons.rule),label:const Text('کنترل مقدماتی ارتفاع بر اساس جدول ۱-۳')),
      if(heightCheck!=null) Card(child:ListTile(leading:Icon(heightCheck!.permitted?Icons.check_circle_outline:Icons.warning_amber_rounded,color:heightCheck!.permitted?Colors.green:Colors.red),title:Text(heightCheck!.hm==null?'غیرمجاز برای SDC انتخابی':heightCheck!.permitted?'حد عددی رعایت شده؛ Hm = ${heightCheck!.hm} m':'حد عددی رعایت نشده؛ Hm = ${heightCheck!.hm} m'),subtitle:Text(heightCheck!.message))),
    ])),
    if(error!=null) Padding(padding:const EdgeInsets.only(top:12),child:Text(error!,style:const TextStyle(color:Colors.red))),
    const SizedBox(height:12),const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('Fs و F1 را می‌توانید دستی وارد کنید یا از جداول ۱-۲ و ۲-۲ با درون‌یابی خطی محاسبه کنید. برای زمین نوع VI، طیف ویژه ساختگاه لازم است و محاسبه جدولی انجام نمی‌شود. گزینه 0.9 برای زمین نوع I در صورت وجود حداقل سه اندازه‌گیری مطمئن ژئوفیزیکی درون‌چاهی، جداگانه باید طبق استاندارد بررسی شود.')))
  ]);
  Widget _results(){final r=result; if(r==null)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('ابتدا در زبانه «ورودی‌ها» پارامترها را وارد کرده و محاسبه کنید.'))); return ListView(padding:const EdgeInsets.all(16),children:[
    const Text('نتایج محاسبات',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),const SizedBox(height:8),
    GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.75,children:[metric('دوره تجربی Te',r.te,unit:'s'),metric('دوره محاسباتی T',r.t,unit:'s'),metric('SMS',r.sms,unit:'g'),metric('SM1',r.sm1,unit:'g'),metric('SDS',r.sds,unit:'g'),metric('SD1',r.sd1,unit:'g'),metric('T0',r.t0,unit:'s'),metric('Ts',r.ts,unit:'s'),metric('Sa(T)',r.sa,unit:'g'),metric('ضریب خام C = Sa/(Ru/Ie)',r.cRaw),metric('حداقل ضریب Cmin',r.cmin),metric('ضریب مؤثر برای C×W',r.c),metric('ضریب توزیع K',r.k)]),
    Card(child:ListTile(leading:const Icon(Icons.info_outline),title:const Text('طبقه‌بندی بر مبنای منطق فایل اکسل'),subtitle:Text('گروه ${r.seismicGroup} · SDC: ${r.sdc?.toString()??'برای Ie واردشده در جدول تعریف نشده'}${(r.ie-0.8).abs()>1e-9&&(r.ie-1.0).abs()>1e-9&&(r.ie-1.2).abs()>1e-9&&(r.ie-1.4).abs()>1e-9?'\nتوجه: جدول SDC در فایل اکسل فقط برای Ie=0.8، 1.0، 1.2 و 1.4 مقدار دارد.':''}'))),
    const SizedBox(height:12),const Text('طیف طرح استاندارد',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const SizedBox(height:6),SizedBox(height:260,child:Card(child:Padding(padding:const EdgeInsets.all(12),child:CustomPaint(painter:SpectrumPainter(r),child:const SizedBox.expand())))),
    const SizedBox(height:8),OutlinedButton.icon(onPressed:()async{await Clipboard.setData(ClipboardData(text:report()));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('گزارش کپی شد.')));},icon:const Icon(Icons.copy),label:const Text('کپی گزارش محاسبات')),
    const Text('طیف و پارامترها بر اساس روابط موجود در فایل اکسل تولید شده‌اند؛ این نمودار، طیف ویژه ساختگاه یا تحلیل خطر مستقل نیست.')
  ]);}
  Widget _distribution()=>ListView(padding:const EdgeInsets.all(16),children:[const Text('توزیع نیروی جانبی در ارتفاع',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('محاسبه آموزشی بر مبنای رابطه توزیع متناسب با Wi × hi^K. برش پایه در این صفحه به‌صورت C × مجموع وزن‌های واردشده فرض می‌شود؛ وزن لرزه‌ای و سایر الزامات باید توسط مهندس تعیین و کنترل شوند.'),const SizedBox(height:16),
    TextField(controller:floorCount,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'تعداد طبقات',border:OutlineInputBorder())),const SizedBox(height:10),TextField(controller:floorHeight,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'ارتفاع ثابت هر طبقه (m)',border:OutlineInputBorder())),const SizedBox(height:10),TextField(controller:floorWeights,maxLines:3,decoration:const InputDecoration(labelText:'وزن لرزه‌ای هر طبقه، از پایین به بالا',hintText:'مثال: 100; 100; 120; 120; 140',border:OutlineInputBorder())),const SizedBox(height:12),FilledButton.icon(onPressed:runDistribution,icon:const Icon(Icons.calculate),label:const Text('محاسبه توزیع طبقات')),
    if(forces.isNotEmpty)...[const SizedBox(height:16),Text('برش پایه محاسباتی: ${(forces.fold<double>(0,(s,f)=>s+f.force)).toStringAsFixed(3)} (واحد وزن ورودی)',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:8),SingleChildScrollView(scrollDirection:Axis.horizontal,child:DataTable(columns:const[DataColumn(label:Text('طبقه')),DataColumn(label:Text('ارتفاع m')),DataColumn(label:Text('وزن')),DataColumn(label:Text('Wi·hi^K')),DataColumn(label:Text('Fi'))],rows:forces.map((f)=>DataRow(cells:[DataCell(Text('${f.floor}')),DataCell(Text(f.height.toStringAsFixed(2))),DataCell(Text(f.weight.toStringAsFixed(2))),DataCell(Text(f.factor.toStringAsFixed(2))),DataCell(Text(f.force.toStringAsFixed(3)))])).toList())),const SizedBox(height:8),OutlinedButton.icon(onPressed:()async{await Clipboard.setData(ClipboardData(text:report()));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('گزارش کپی شد.')));},icon:const Icon(Icons.copy),label:const Text('کپی جدول و گزارش'))]
  ]);
  Widget _about()=>ListView(padding:const EdgeInsets.all(16),children:[const Text('راهنما و دامنه اعتبار',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:12),
    const _InfoCard(title:'منبع محاسبات',body:'روابط اصلی این نسخه از فایل اکسل «محاسبه ضریب زلزله استاندارد 2800 - ویرایش 5» استخراج شده‌اند. فایل PDF تفسیری ارائه‌شده نیز شامل مطالبی درباره طیف طرح، ضرایب ساختگاه و طیف قائم است؛ این موارد هنوز به‌طور کامل در برنامه پیاده‌سازی نشده‌اند.'),
    const _InfoCard(title:'ماژول‌های موجود',body:'• محاسبه Te و T\n• محاسبه SMS، SM1، SDS و SD1\n• طیف افقی Sa(T) و نمودار آن\n• محاسبه Cmin، C و K؛ Cmin بر اساس روابط ۳-۳ تا ۳-۵ استاندارد اصلاح شده است\n• طبقه‌بندی گروه لرزه‌ای/SDC در محدوده مقادیر موجود در جدول اکسل\n• توزیع نیروی جانبی طبقات با Wi·hi^K\n• تولید گزارش متنی قابل کپی'),
    const _InfoCard(title:'ماژول‌های تکمیل‌نشده',body:'• بانک شهرها برای تعیین خودکار Ss و S1\n• طیف قائم و طیف ویژه ساختگاه\n• ارزیابی خودکار تمام شروط یادداشت‌های [۱] تا [۷] جدول ۱-۳؛ فهرست ۴۲ ردیف دارد اما شروط و استثناها نیازمند بررسی دستی‌اند\n• کنترل نامنظمی‌ها و الزامات تحلیل\n• ذخیره/بازیابی پروژه‌ها\n• خروجی PDF رسمی و فایل اکسل خروجی\n• تطبیق بندبه‌بند با متن رسمی و مثال‌های حل‌شده'),
    const _InfoCard(title:'هشدار حرفه‌ای',body:'این برنامه ابزار کمکی و نسخه توسعه‌ای است؛ خروجی آن نباید بدون کنترل مهندس مسئول و تطبیق با متن رسمی استاندارد ۲۸۰۰ ویرایش پنجم، اصلاحیه‌ها و ضوابط مکمل برای طراحی نهایی استفاده شود. هرجا فایل اکسل مرجع ناقص یا مبهم باشد، برنامه نباید آن را به‌عنوان حکم قطعی آیین‌نامه معرفی کند.')
  ]);
}

class _InfoCard extends StatelessWidget { final String title,body; const _InfoCard({required this.title,required this.body}); @override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),Text(body)]))); }

class SpectrumPainter extends CustomPainter {
  final Results r; SpectrumPainter(this.r);
  @override void paint(Canvas canvas,Size size){
    const left=42.0,right=12.0,top=12.0,bottom=32.0; final w=size.width-left-right,h=size.height-top-bottom;
    final maxT=8.0; final maxSa=math.max(r.sds*1.2, r.sd1/math.max(r.t0,0.05)*0.5);
    Offset pt(double t,double sa)=>Offset(left+w*t/maxT,top+h*(1-sa/maxSa));
    final axis=Paint()..color=Colors.grey..strokeWidth=1; canvas.drawLine(Offset(left,top),Offset(left,top+h),axis);canvas.drawLine(Offset(left,top+h),Offset(left+w,top+h),axis);
    final grid=Paint()..color=Colors.grey.withOpacity(0.25)..strokeWidth=0.7;
    for(var i=1;i<=4;i++){final y=top+h*i/5;canvas.drawLine(Offset(left,y),Offset(left+w,y),grid);}
    for(var i=1;i<=4;i++){final x=left+w*i/5;canvas.drawLine(Offset(x,top),Offset(x,top+h),grid);}
    final path=Path(); for(var i=0;i<=240;i++){final t=maxT*i/240;final sa=spectrumAt(t,r.sds,r.sd1,r.t0,r.ts,r.tl);final p=pt(t,sa);if(i==0)path.moveTo(p.dx,p.dy);else path.lineTo(p.dx,p.dy);}
    canvas.drawPath(path,Paint()..color=const Color(0xFF0E7490)..strokeWidth=2.5..style=PaintingStyle.stroke);
    final marker=pt(r.t,r.sa);canvas.drawCircle(marker,4,Paint()..color=Colors.deepOrange);canvas.drawCircle(marker,4,Paint()..color=Colors.white..style=PaintingStyle.stroke..strokeWidth=1.5);
    void label(String s,Offset p,{TextAlign align=TextAlign.left}){final tp=TextPainter(text:TextSpan(text:s,style:const TextStyle(color:Colors.grey,fontSize:10)),textDirection:TextDirection.ltr,textAlign:align)..layout();tp.paint(canvas,p);}
    label('Sa (g)',const Offset(2,0));label('0',Offset(left-8,top+h+5));label('T (s)',Offset(left+w-24,top+h+10));label('8',Offset(left+w-3,top+h+5));label(maxSa.toStringAsFixed(2),Offset(2,top-2));label('T=${r.t.toStringAsFixed(2)}',Offset((marker.dx+5).clamp(left,left+w-45).toDouble(), (marker.dy-18).clamp(top,top+h-12).toDouble()));
  }
  @override bool shouldRepaint(covariant SpectrumPainter oldDelegate)=>oldDelegate.r.t!=r.t||oldDelegate.r.sds!=r.sds||oldDelegate.r.sd1!=r.sd1;
}
