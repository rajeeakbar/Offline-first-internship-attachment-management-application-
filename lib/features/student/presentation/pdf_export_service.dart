import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import '../../../core/services/local_database.dart';

class PdfExportService {
  static Future<void> generateStudentLogReport(String studentId, String studentName) async {
    debugPrint('Generating PDF report for student: $studentName');
    final pdf = pw.Document();
    final db = await LocalDatabase.instance.database;

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
              children: [
                pw.Text('UNIVERSITY INDUSTRIAL ATTACHMENT LOG', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                // Placeholder for Logo
                pw.PdfLogo(),
              ],
            ),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Student Name: $studentName'),
                pw.Text('Student ID: ${studentId.split('-').last}'),
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
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
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
