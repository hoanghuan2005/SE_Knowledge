import '../models/curriculum.dart';

/// Dữ liệu mẫu khung chương trình ngành Kỹ thuật Phần mềm (SE) phục vụ demo offline
class CurriculumMockData {
  CurriculumMockData._();

  static Curriculum get defaultCurriculum => const Curriculum(
        major: 'Kỹ thuật phần mềm (Software Engineering - SE)',
        semesters: [
          Semester(
            termNumber: 1,
            courses: [
              Course(
                code: 'PRF192',
                name: 'Programming Fundamentals (C)',
                credits: 3,
                prerequisites: [],
                term: 1,
              ),
              Course(
                code: 'CEA201',
                name: 'Computer Organization and Architecture',
                credits: 3,
                prerequisites: [],
                term: 1,
              ),
              Course(
                code: 'CSI104',
                name: 'Introduction to Computer Science',
                credits: 3,
                prerequisites: [],
                term: 1,
              ),
              Course(
                code: 'MAE101',
                name: 'Mathematics for Engineering',
                credits: 3,
                prerequisites: [],
                term: 1,
              ),
            ],
          ),
          Semester(
            termNumber: 2,
            courses: [
              Course(
                code: 'PRO192',
                name: 'Object-Oriented Programming (Java)',
                credits: 3,
                prerequisites: ['PRF192'],
                term: 2,
              ),
              Course(
                code: 'MAD101',
                name: 'Discrete Mathematics',
                credits: 3,
                prerequisites: [],
                term: 2,
              ),
              Course(
                code: 'OSG202',
                name: 'Operating Systems',
                credits: 3,
                prerequisites: [],
                term: 2,
              ),
              Course(
                code: 'NWC203c',
                name: 'Computer Networking',
                credits: 3,
                prerequisites: [],
                term: 2,
              ),
            ],
          ),
          Semester(
            termNumber: 3,
            courses: [
              Course(
                code: 'CSD201',
                name: 'Data Structures and Algorithms',
                credits: 3,
                prerequisites: ['PRO192'],
                term: 3,
              ),
              Course(
                code: 'DBI202',
                name: 'Introduction to Databases (SQL)',
                credits: 3,
                prerequisites: [],
                term: 3,
              ),
              Course(
                code: 'LAB211',
                name: 'OOP Java Lab Project',
                credits: 3,
                prerequisites: ['PRO192'],
                term: 3,
              ),
              Course(
                code: 'MAS291',
                name: 'Statistics and Probability',
                credits: 3,
                prerequisites: ['MAE101'],
                term: 3,
              ),
            ],
          ),
        ],
      );
}
