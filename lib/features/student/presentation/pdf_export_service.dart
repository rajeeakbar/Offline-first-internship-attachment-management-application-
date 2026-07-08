import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../core/services/local_database.dart';

class PdfExportService {
  static Future<void> generateStudentLogReport(String studentId, String studentName) async {
    debugPrint('Generating PDF report for student: $studentName');
    final pdf = pw.Document();
    final db = await LocalDatabase.instance.database;

    // Load institution logo
    pw.ImageProvider? logoImage;
    try {
      final ByteData bytes = await rootBundle.load('assets/images/logo.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('Error loading logo for PDF: $e');
    }

    // Fetch student profile details (ID number and Level)
    final profileResult = await db.query('profiles', where: 'id = ?', whereArgs: [studentId]);
    final String studentIdNumber = profileResult.isNotEmpty ? (profileResult.first['student_id_number']?.toString() ?? 'N/A') : 'N/A';
    final String studentLevel = profileResult.isNotEmpty ? (profileResult.first['level']?.toString() ?? 'N/A') : 'N/A';

    // Fetch institution name from settings
    final settingsResult = await db.query('app_settings', where: 'key = ?', whereArgs: ['institution_name']);
    final String schoolName = settingsResult.isNotEmpty ? (settingsResult.first['value']?.toString() ?? 'INDUSTRIAL ATTACHMENT UNIVERSITY') : 'INDUSTRIAL ATTACHMENT UNIVERSITY';

    final logs = await db.query('log_entries',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'date ASC'
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (context) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Container(
                    width: 60,
                    height: 60,
                    child: pw.Image(logoImage),
                  )
                else
                  pw.Container(width: 60, height: 60, child: pw.PdfLogo()),
                pw.SizedBox(width: 15),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(schoolName.toUpperCase(),
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      pw.Text('INDUSTRIAL ATTACHMENT LOGBOOK REPORT',
                          textAlign: pw.TextAlign.right,
                          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 2, color: PdfColors.indigo900),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('STUDENT NAME: $studentName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('STUDENT ID: $studentIdNumber'),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('LEVEL: $studentLevel', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text('REPORT DATE: ${DateTime.now().toString().split(' ')[0]}'),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
          ],
        ),
        build: (context) => [
          pw.Table.fromTextArray(
            headers: ['Day', 'Date', 'Description of Work', 'Knowledge Gained', 'Status'],
            data: logs.map((log) => [
              log['day_number']?.toString() ?? '-',
              log['date'].toString().split('T')[0],
              log['work_description'],
              log['knowledge_acquired'],
              log['status'],
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
            cellAlignment: pw.Alignment.centerLeft,
            cellHeight: 30,
            cellPadding: const pw.EdgeInsets.all(5),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(color: PdfColors.grey)),
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}
