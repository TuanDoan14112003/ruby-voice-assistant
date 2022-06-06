from csv import DictReader
def case_counts(tests, counts, max_day):
    cases = [0] * max_day
    with open(tests) as infile:
        test_reader = DictReader(infile)
        for row in test_reader:
            if row['result'] == 'positive':
                cases[int(row['day'])] += 1
    with open(counts) as outfile:
        for day, count in enumerate(cases):
            outfile.write(f'{day},{count} \n')

case_counts('tests.csv','counts.csv',10)

