import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:standard_2800_v5/main.dart';

void main() {
  test('matches key workbook relations for the default example', () {
    final r = calculate(h: 15, ie: 1, system: 2, ru: 4.5, ss: 1.4, s1: 0.6, fs: 1, f1: 1.3, ta: 1);
    expect(r.te, closeTo(0.047 * math.pow(15.0, 0.9), 1e-8));
    expect(r.t, greaterThan(0)); expect(r.sms, closeTo(1.4, 1e-8)); expect(r.sm1, closeTo(0.78, 1e-8));
    expect(r.sds, closeTo((2 / 3) * 1.4, 1e-8)); expect(r.sd1, closeTo((2 / 3) * 0.6 * 1.3, 1e-8));
    expect(r.c, greaterThan(0)); expect(r.sdc, isNotNull);
  });
  test('empirical period exponents match equations 6-3 to 9-3 in Standard 2800 v5', () {
    const h = 15.0;
    final expected = <int, double>{
      1: 0.072 * 15.0, // replaced below with explicit powers
      2: 0.047 * 15.0,
      3: 0.049 * 15.0,
      4: 0.073 * 15.0,
      5: 0.049 * 15.0,
      6: 0.049 * 15.0,
    };
    expected[1] = (0.072 * math.pow(h, 0.8)).toDouble();
    expected[2] = (0.047 * math.pow(h, 0.9)).toDouble();
    expected[3] = (0.049 * math.pow(h, 0.75)).toDouble();
    expected[4] = (0.073 * math.pow(h, 0.75)).toDouble();
    expected[5] = (0.049 * math.pow(h, 0.75)).toDouble();
    expected[6] = (0.049 * math.pow(h, 0.75)).toDouble();
    for (final entry in expected.entries) {
      final r = calculate(h: h, ie: 1, system: entry.key, ru: 4.5, ss: 1.4, s1: 0.6, fs: 1, f1: 1.3, ta: 10);
      expect(r.te, closeTo(entry.value, 1e-8), reason: 'system ${entry.key}');
    }
  });

  test('always applies baseline minimum coefficient and adds S1 lower bound when S1 >= 0.6', () {
    final a=calculate(h:15,ie:1,system:2,ru:4.5,ss:1.4,s1:0.6,fs:1,f1:1.3,ta:1);
    expect(a.cmin,closeTo(0.5*0.6/4.5,1e-8));
    final b=calculate(h:15,ie:1,system:2,ru:4.5,ss:1.4,s1:0.5,fs:1,f1:1.3,ta:1);
    expect(b.cmin,closeTo(math.max(0.044 * b.sds * b.ie, 0.01),1e-8));
  });
  test('site factors reproduce tabulated points and linear interpolation', () {
    final exact = siteFactors(soilType: 2, ss: 0.5, s1: 0.2);
    expect(exact.fs, closeTo(1.2, 1e-8));
    expect(exact.f1, closeTo(1.5, 1e-8));
    final mid = siteFactors(soilType: 3, ss: 0.875, s1: 0.25);
    expect(mid.fs, closeTo(1.15, 1e-8));
    expect(mid.f1, closeTo(2.15, 1e-8));
    final high = siteFactors(soilType: 4, ss: 2.0, s1: 0.8);
    expect(high.fs, closeTo(1.1, 1e-8));
    expect(high.f1, closeTo(2.8, 1e-8));
  });

  test('all tabulated site-factor knots reproduce Standard 2800 fifth-edition values', () {
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
    for (var soil = 1; soil <= 5; soil++) {
      for (var i = 0; i < ssKnots.length; i++) {
        final r = siteFactors(soilType: soil, ss: ssKnots[i], s1: 0.3);
        expect(r.fs, closeTo(fsRows[soil]![i], 1e-10), reason: 'Fs soil $soil at Ss=${ssKnots[i]}');
      }
      for (var i = 0; i < s1Knots.length; i++) {
        final r = siteFactors(soilType: soil, ss: 0.75, s1: s1Knots[i]);
        expect(r.f1, closeTo(f1Rows[soil]![i], 1e-10), reason: 'F1 soil $soil at S1=${s1Knots[i]}');
      }
    }
  });

  test('Table 1-3 height limits are checked for selected common systems', () {
    final ok = checkHeightLimit(systemId: 'moment_special_rc', sdc: 2, height: 70);
    expect(ok.permitted, isTrue);
    expect(ok.hm, 70);
    final tooTall = checkHeightLimit(systemId: 'moment_special_steel', sdc: 3, height: 81);
    expect(tooTall.permitted, isFalse);
    expect(tooTall.hm, 80);
    final prohibited = checkHeightLimit(systemId: 'moment_ordinary_rc', sdc: 2, height: 8);
    expect(prohibited.permitted, isFalse);
    expect(prohibited.hm, isNull);
  });
  test('height-limit catalogue covers the complete Table 1-3 row set', () {
    expect(heightLimitSystems.length, 42);
    expect(heightLimitSystems.map((x) => x.id).toSet().length, 42);
    expect(heightLimitSystems.every((x) => x.ru > 0 && x.hmBySdc.length == 3), isTrue);
    expect(heightLimitSystems.firstWhere((x) => x.id == 'moment_special_rc').ru, 6.5);
    expect(heightLimitSystems.firstWhere((x) => x.id == 'dual_intermediate_moment_special_composite_scbrace').hmBySdc, [35, 28, 15]);
  });

  test('height check exposes conditional notes instead of implying full code compliance', () {
    final note3 = checkHeightLimit(systemId: 'frame_special_rc_wall', sdc: 2, height: 45);
    expect(note3.permitted, isTrue);
    expect(note3.message, contains('یادداشت ۳'));
    expect(note3.message, contains('به معنی تأیید کامل انطباق آیین‌نامه‌ای نیست'));
    final note5 = checkHeightLimit(systemId: 'moment_special_rc', sdc: 2, height: 40);
    expect(note5.permitted, isTrue);
    expect(note5.message, contains('یادداشت‌های جدول'));
  });

  test('height limit validation rejects invalid inputs', () {
    expect(() => checkHeightLimit(systemId: 'moment_special_rc', sdc: 4, height: 10), throwsArgumentError);
    expect(() => checkHeightLimit(systemId: 'unknown', sdc: 1, height: 10), throwsArgumentError);
    expect(() => checkHeightLimit(systemId: 'moment_special_rc', sdc: 1, height: 0), throwsArgumentError);
  });

  test('site type VI and out-of-table lower bounds are rejected', () {
    expect(() => siteFactors(soilType: 6, ss: 1.0, s1: 0.3), throwsArgumentError);
    expect(() => siteFactors(soilType: 2, ss: 0.4, s1: 0.3), throwsArgumentError);
    expect(() => siteFactors(soilType: 2, ss: 1.0, s1: 0.1), throwsArgumentError);
  });

  test('spectrum follows four workbook branches', () {
    expect(spectrumAt(0,1,0.5,0.1,0.5,6),closeTo(0.4,1e-8));
    expect(spectrumAt(0.1,1,0.5,0.1,0.5,6),closeTo(1,1e-8));
    expect(spectrumAt(1,1,0.5,0.1,0.5,6),closeTo(0.5,1e-8));
    expect(spectrumAt(6,1,0.5,0.1,0.5,6),closeTo(0.5*6/(6*6),1e-8));
  });
  test('distributes base shear with sum of floor forces equal to base shear', () {
    final fs=distributeBaseShear(heights:[3,6,9],weights:[100,100,100],baseShear:30,k:1);
    expect(fs.length,3); expect(fs.fold<double>(0,(s,f)=>s+f.force),closeTo(30,1e-8));
    expect(fs[2].force,greaterThan(fs[0].force));
  });

  test('SDC lookup tolerates floating-point representation of supported Ie', () {
    final r = calculate(h: 15, ie: 1.20000000000001, system: 2, ru: 4.5, ss: 1.4, s1: 0.6, fs: 1, f1: 1.3, ta: 1);
    expect(r.sdc, isNotNull);
  });
  test('returns no SDC when Ie is outside workbook lookup table', () {
    final r = calculate(h: 15, ie: 1.1, system: 2, ru: 4.5, ss: 1.4, s1: 0.6, fs: 1, f1: 1.3, ta: 1);
    expect(r.sdc, isNull);
  });
  test('rejects invalid inputs', () {
    expect(() => calculate(h:0,ie:1,system:2,ru:4.5,ss:1.4,s1:0.6,fs:1,f1:1.3,ta:1),throwsArgumentError);
    expect(() => distributeBaseShear(heights:[3,2],weights:[10,10],baseShear:5,k:1),throwsArgumentError);
    expect(() => spectrumAt(double.nan,1,0.5,0.1,0.5,6),throwsArgumentError);
    expect(() => distributeBaseShear(heights:[3],weights:[10],baseShear:double.infinity,k:1),throwsArgumentError);
  });
  test('numerical benchmark A: supplied workbook defaults', () {
    final r = calculate(h:15, ie:1, system:2, ru:4.5, ss:1.4, s1:0.6, fs:1, f1:1.3, ta:1);
    expect(r.te, closeTo(0.5377494701, 1e-8));
    expect(r.t, closeTo(0.7528492581, 1e-8));
    expect(r.sa, closeTo(0.6907093212, 1e-8));
    expect(r.cmin, closeTo(0.0666666667, 1e-8));
    expect(r.cRaw, closeTo(r.sa / (r.ru / r.ie), 1e-10));
    expect(r.c, closeTo(0.1534909603, 1e-8));
    expect(r.k, closeTo(1.1264246291, 1e-8));
  });


  test('reports raw seismic coefficient separately from minimum-adjusted coefficient', () {
    final r = calculate(h:15, ie:1, system:2, ru:4.5, ss:1.4, s1:0.6, fs:1, f1:1.3, ta:1);
    expect(r.cRaw, closeTo(r.sa / (r.ru / r.ie), 1e-10));
    expect(r.c, closeTo(math.max(r.cRaw, r.cmin), 1e-10));
    expect(r.c, greaterThanOrEqualTo(r.cRaw));
    expect(r.c, greaterThanOrEqualTo(r.cmin));
  });

  test('numerical benchmark B: S1 below 0.6 retains baseline Cmin', () {
    final r = calculate(h:30, ie:1.2, system:1, ru:6.5, ss:1.0, s1:0.4, fs:1.1, f1:2.1, ta:2.0);
    expect(r.te, closeTo(1.094031, 1e-6));
    expect(r.t, closeTo(1.531643, 1e-6));
    expect(r.sds, closeTo(0.7333333333, 1e-8));
    expect(r.sd1, closeTo(0.56, 1e-8));
    expect(r.cmin, closeTo(0.03872, 1e-8));
    expect(r.c, closeTo(0.0674991619, 1e-7));
    expect(r.k, closeTo(1.5158215, 1e-6));
  });

  test('numerical benchmark C: high S1 and long-period spectrum branch', () {
    final r = calculate(h:70, ie:1.4, system:3, ru:6.5, ss:1.5, s1:0.6, fs:1.1, f1:2.8, ta:3.0);
    expect(r.te, closeTo(1.185822, 1e-6));
    expect(r.t, closeTo(1.660151, 1e-6));
    expect(r.sa, closeTo(0.674637, 1e-6));
    expect(r.cmin, closeTo(0.06776, 1e-6));
    expect(r.c, closeTo(0.1453065, 1e-6));
    expect(r.k, closeTo(1.5800755, 1e-6));
  });

}
