-- table creation
CREATE TABLE Author(
auth_ID varchar(5) primary key not null,
fname varchar(20) not null,
lname varchar(20) not null
)

CREATE TABLE Member(
memb_ID varchar(5) primary key not null,
memb_Name varchar(20) not null,
memb_Status varchar(10) not null,
memb_Type varchar(10) not null,
CONSTRAINT check_memb_status CHECK(memb_status in ('Inactive', 'Active',
'Suspended')),
CONSTRAINT check_memb_type CHECK(memb_type in ('Student', 'Lecturer'))
)

CREATE TABLE ColorTag(
tag_ID varchar(2) primary key not null,
book_Type varchar(20) not null,
loan_Period int not null
)

CREATE TABLE Category(
cat_ID varchar(5) primary key not null,
cat_Name varchar(50) not null,
cat_Keyword varchar(20) not null
)

CREATE TABLE Book(
book_ID varchar(5) primary key not null,
cat_ID varchar(5) not null,
tag_ID varchar(2) not null,
book_Amt smallint not null,
book_Title varchar(50) not null,
pub_Year int not null,
FOREIGN KEY(cat_ID) REFERENCES Category,
FOREIGN KEY(tag_ID) REFERENCES ColorTag
)

CREATE TABLE BookAuthor(
book_ID varchar(5) not null,
auth_ID varchar(5) not null,
primary key(book_ID, auth_ID),
FOREIGN KEY(book_ID) REFERENCES Book,
FOREIGN KEY(auth_ID) REFERENCES Author
)

CREATE TABLE BookDetail(
bookDetail_ID int generated always as identity(start with 1, increment by 1)
primary key not null,
book_ID varchar(5) not null,
barcode varchar(10) UNIQUE not null,
FOREIGN KEY(book_ID) REFERENCES Book
)

CREATE TABLE Loan(
loan_ID varchar(5) primary key not null,
memb_ID varchar(5) not null,
loan_Date date DEFAULT current date,
return_Status varchar(10) not null DEFAULT ‘No’ CHECK(return_Status in
('Yes','No')),
FOREIGN KEY (memb_ID) REFERENCES Member
)

CREATE TABLE LoanDetail(
loanDetail_ID varchar(5) primary key not null,
loan_ID varchar(5) not null,
bookDetail_ID int not null,
return_Date date DEFAULT null,
FOREIGN KEY(loan_ID) REFERENCES Loan,
FOREIGN KEY(bookDetail_ID) REFERENCES BookDetail
)

CREATE TABLE Reservation(
memb_ID varchar(5) not null,
reserve_Date date not null,
bookDetail_ID int not null,
reserve_Status varchar(10) DEFAULT 'Pending' CHECK(reserve_status in
('Cancelled', 'Pending', 'Expired', 'Completed')),
primary key(memb_ID,reserve_Date),
FOREIGN KEY (memb_ID) REFERENCES Member,
FOREIGN KEY (bookDetail_ID) REFERENCES BookDetail
)

CREATE TABLE Fine(
fine_ID varchar(5) primary key not null,
loanDetail_ID varchar(5) not null UNIQUE,
fine_Date date DEFAULT current date not null,
fine_Amt decimal(5, 2) not null,
payment_Date date DEFAULT null,
FOREIGN KEY (loanDetail_ID) REFERENCES LoanDetail
)

-- data manipulation with SQL
-- find total no. of books in a category
SELECT c.cat_name, COUNT(DISTINCT b.book_title) AS distinct_books
FROM category c
JOIN book b ON c.cat_id = b.cat_id
GROUP BY c.cat_name

-- find latest publication year and earliest publication year of books
SELECT DISTINCT book_title,
MAX(pub_year) AS latest_pub_year,
MIN(pub_year) AS earliest_pub_year
FROM book
GROUP BY book_title

--  find the total number of members according to Student, Lecturer, Total Active, Total
Suspended and Total Inactive
SELECT
memb_type,
COUNT(*) AS total_member,
SUM(CASE WHEN memb_Status = 'Active' THEN 1 ELSE 0 END) AS
Total_Active_Member,
SUM(CASE WHEN memb_Status = 'Suspended' THEN 1 ELSE 0 END) AS
Total_Suspended_Member,
SUM(CASE WHEN memb_Status = 'Inactive' THEN 1 ELSE 0 END) AS
Total_Inactive_Member
FROM
member
WHERE
memb_type IN ('Student', 'Lecturer')
GROUP BY
memb_type

-- calculate total number of books loaned and the number of books that have not
returned in each month
SELECT
c.cat_Name,
CAST(MONTHNAME(l.loan_date) AS VARCHAR(20)) AS loan_month,
COUNT(*) AS total_loan,
SUM(CASE WHEN ld.return_date IS NULL THEN 1 ELSE 0 END) AS
Books_Not_Returned
FROM
loan l
JOIN
loandetail ld ON l.loan_id = ld.loan_id
JOIN
bookdetail bd ON ld.bookdetail_id = bd.bookdetail_id
JOIN
book b ON bd.book_id = b.book_id
JOIN
category c ON b.cat_id = c.cat_id
GROUP BY
c.cat_Name, CAST(MONTHNAME(l.loan_date) AS VARCHAR(20)),
MONTH(l.loan_date)
HAVING
COUNT(*) > 0
ORDER BY
MONTH(l.loan_date)

-- view top 3 books rented out within a month
CREATE VIEW top_3_loan AS
SELECT subq.book_id, subq.book_title, subq.rental_count
FROM (
SELECT BD.book_id, B.book_title, COUNT(*) AS rental_count
FROM loan L
JOIN loandetail LD ON L.loan_id = LD.loan_id
JOIN bookDetail BD ON LD.bookdetail_id = BD.bookdetail_id
JOIN book B ON BD.book_id = B.book_id
WHERE L.loan_date >= TRUNCATE(CURRENT DATE, 'MONTH')
GROUP BY BD.book_id, B.book_title
ORDER BY rental_count DESC
FETCH FIRST 3 ROWS ONLY
) AS subq

SELECT * FROM top_3_loan

-- trigger to ensure records of bookdetail is parallel with the book_amt
CREATE TRIGGER check_bookdetail_data
BEFORE INSERT ON bookdetail
REFERENCING NEW AS new_row
FOR EACH ROW
BEGIN
DECLARE book_amt INT;
SET book_amt = (SELECT book_amt FROM book WHERE book_id =
new_row.book_id);
IF book_amt = (SELECT COUNT(*) FROM bookdetail WHERE book_id =
new_row.book_id) THEN
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot insert
more records into bookdetail for this book_id';
END IF;
END

-- trigger to verify member eligibility to loan books
CREATE TRIGGER LoanEligibility
BEFORE INSERT ON Loan
REFERENCING NEW AS new
FOR EACH ROW mode db2sql
BEGIN
DECLARE overdueFines DECIMAL(5,2);
DECLARE memberStatus VARCHAR(10);
DECLARE errorMessage VARCHAR(1000);
SELECT COALESCE(SUM(fine_amt), 0)
INTO overdueFines
FROM Fine
JOIN loandetail ld ON ld.loandetail_id = fine.loandetail_id
JOIN loan l ON l.loan_id = ld.loan_id
WHERE l.memb_id = new.memb_id
AND fine.payment_date IS NULL;
SELECT memb_status INTO memberStatus
FROM Member
WHERE memb_id = new.memb_id;
IF overdueFines > 0 THEN
SET errorMessage = 'You have outstanding fines: RM' ||
CAST(overdueFines AS VARCHAR(10)) || ', settle them before making new
loan.';
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = errorMessage;
END IF;
IF memberStatus <> 'Active' THEN
SET errorMessage = 'Your member status: ' || memberStatus || ',
contact library for further assistance.';
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = errorMessage;
END IF;
END

-- trigger to check availability of book for loan
CREATE TRIGGER loan_available
BEFORE INSERT ON loandetail
REFERENCING NEW AS new_row
FOR EACH ROW MODE DB2SQL
BEGIN
DECLARE book_loan_count INT;
DECLARE book_reservation_count INT;
IF EXISTS (
SELECT *
FROM loandetail
WHERE bookdetail_id = new_row.bookdetail_id
AND return_date IS NULL
)
THEN
SET book_loan_count = 1;
ELSE
SET book_loan_count = 0;
END IF;
IF EXISTS (
SELECT *
FROM reservation
WHERE bookdetail_id = new_row.bookdetail_id
AND reserve_status = 'Pending'
)
THEN
SET book_reservation_count = 1;
ELSE
SET book_reservation_count = 0;
END IF;
IF book_reservation_count > 0 THEN
SIGNAL SQLSTATE '75001' SET MESSAGE_TEXT = 'The book is
currently being reserved.';
ELSEIF book_loan_count > 0 THEN
SIGNAL SQLSTATE '75001' SET MESSAGE_TEXT = 'The book is
currently loaned out.';
END IF;
END

-- trigger to check availability of book for reservation
CREATE TRIGGER rsv_available
BEFORE INSERT ON reservation
REFERENCING NEW AS new_row
FOR EACH ROW MODE DB2SQL
BEGIN
DECLARE book_loan_count INT;
DECLARE book_reservation_count INT;
IF EXISTS (
SELECT 1
FROM loandetail
WHERE bookdetail_id = new_row.bookdetail_id
)
THEN
SELECT COUNT(*) INTO book_loan_count
FROM loan l
JOIN loandetail ld ON l.loan_id = ld.loan_id
WHERE ld.bookdetail_id = new_row.bookdetail_id
AND ld.return_date IS NULL;
ELSE
SET book_loan_count = 0;
END IF;
IF EXISTS (
SELECT 1
FROM reservation
WHERE bookdetail_id = new_row.bookdetail_id
)
THEN
SELECT COUNT(*) INTO book_reservation_count
FROM reservation r
WHERE r.bookdetail_id = new_row.bookdetail_id
AND r.reserve_status ='Pending';
ELSE
SET book_reservation_count = 0;
END IF;
IF book_loan_count > 0 THEN
SIGNAL SQLSTATE '75001' SET MESSAGE_TEXT = 'The book is
currently loaned out.';
ELSEIF book_reservation_count > 0 THEN
SIGNAL SQLSTATE '75001' SET MESSAGE_TEXT = 'The book is
currently being reserved.';
END IF;
END

-- trigger to generate fine_id automatically
CREATE TRIGGER autoFineId
BEFORE INSERT ON fine
REFERENCING NEW AS new
FOR EACH ROW
WHEN (new.fine_id IS NULL)
BEGIN ATOMIC
SET new.fine_id = CONCAT('F', CHAR(next value for fine_id_seq));
END

-- trigger to update return status of each loan
CREATE TRIGGER triggerReturn
AFTER UPDATE ON loandetail
REFERENCING OLD AS old_row
FOR EACH ROW
MODE DB2SQL
BEGIN
UPDATE loan SET return_status = 'Yes' WHERE return_status IS NOT
NULL AND old_row.loan_id = loan.loan_id;
END

-- trigger to count max books a member can loan
CREATE TRIGGER loanlimit
BEFORE INSERT ON loan
REFERENCING NEW AS new_row
FOR EACH ROW BEGIN DECLARE total_loans INT;
DECLARE member_type VARCHAR(10);
SELECT memb_type
INTO member_type
FROM member WHERE memb_id = new_row.memb_id;
SELECT COUNT(*)
INTO total_loans
FROM loandetail ld
JOIN loan l ON ld.loan_id = l.loan_id
WHERE l.memb_id = new_row.memb_id
AND l.return_status = 'No'; IF (member_type = 'Student' AND
total_loans >= 2) OR (member_type = 'Lecturer' AND total_loans >= 10)
THEN SIGNAL SQLSTATE '45000'
SET MESSAGE_TEXT = 'Loan limit exceeded for the borrower.';
END IF;
END

-- stored procedure to search books by keyword, author or title
CREATE PROCEDURE searchBook(IN searchType VARCHAR(10), IN searchValue
VARCHAR(20))
BEGIN
DECLARE c1 CURSOR WITH RETURN FOR
SELECT b.book_id, b.cat_id, b.tag_id, b.book_amt, b.book_title,
b.pub_year
FROM book b
WHERE b.book_id IN (
SELECT bc.book_id
FROM category c, book bc
WHERE c.cat_id = bc.cat_id
AND UPPER(c.cat_keyword) = UPPER(searchValue)
)
ORDER BY b.book_title;
DECLARE c2 CURSOR WITH RETURN FOR
SELECT b.book_id, b.cat_id, b.tag_id, b.book_amt, b.book_title,
b.pub_year
FROM book b
INNER JOIN bookauthor ba ON b.book_id = ba.book_id
INNER JOIN author a ON ba.auth_id = a.auth_id
WHERE UPPER(a.fname) = UPPER(searchValue)
OR UPPER(a.lname) = UPPER(searchValue)
OR UPPER(a.fname || ' ' || a.lname) = UPPER(searchValue)
ORDER BY b.book_title;
DECLARE c3 CURSOR WITH RETURN FOR
SELECT b.book_id, b.cat_id, b.tag_id, b.book_amt, b.book_title,
b.pub_year
FROM book b
WHERE UPPER(b.book_title) LIKE '%' || UPPER(searchValue) || '%'
ORDER BY b.book_title;
IF UPPER(searchType) = 'KEYWORD' THEN
OPEN c1;
ELSEIF UPPER(searchType) = 'AUTHOR' THEN
OPEN c2;
ELSEIF UPPER(searchType) = 'TITLE' THEN
OPEN c3;
ELSE
SIGNAL SQLSTATE '38000' SET MESSAGE_TEXT = 'Invalid search type
provided. Please enter KEYWORD, AUTHOR, or TITLE';
END IF;
END


-- stored procedure to automatically update book return details
CREATE PROCEDURE updateReturn(IN ld_id VARCHAR(5))
BEGIN
DECLARE c CURSOR WITH RETURN FOR
SELECT * FROM loandetail join loan on loandetail.loan_id =
loan.loan_id;
UPDATE loandetail
SET return_date = CURRENT DATE
WHERE loandetail_id = ld_id;
UPDATE loan
SET return_status = 'Yes'
WHERE loan_id = (SELECT loan_id FROM loandetail WHERE loandetail_id
= ld_id);
OPEN c;
END

-- stored procedure to check expiry of book reservation
CREATE PROCEDURE updateExpiry
LANGUAGE SQL
BEGIN
DECLARE c CURSOR WITH RETURN FOR
SELECT * FROM reservation;
FOR v_row AS
SELECT * FROM reservation
DO
IF (v_row.reserve_status = 'Pending') THEN
UPDATE reservation
SET reserve_status = 'Expired'
WHERE reserve_date < CURRENT DATE - 2 DAYS
AND reserve_status = 'Pending';
END IF;
END FOR;
OPEN c;
END

-- stored procedure to update member status
CREATE PROCEDURE updateMem
BEGIN
DECLARE v_memb_id VARCHAR(10);
DECLARE v_payment_date DATE;
FOR suspended_members AS
SELECT m.memb_id, f.payment_date
FROM member m
JOIN loan l ON l.memb_id = m.memb_id
JOIN loandetail ld ON ld.loan_id = l.loan_id
JOIN fine f ON f.loandetail_id = ld.loandetail_id
WHERE f.payment_date IS NULL
OR ld.return_date IS NULL
DO
SET v_memb_id = suspended_members.memb_id;
SET v_payment_date = suspended_members.payment_date;
UPDATE member SET memb_status = 'Suspended' WHERE memb_id =
v_memb_id;
END FOR;
FOR active_members AS
SELECT m.memb_id, f.payment_date
FROM member m
JOIN loan l ON l.memb_id = m.memb_id
JOIN loandetail ld ON ld.loan_id = l.loan_id
JOIN fine f ON f.loandetail_id = ld.loandetail_id
WHERE f.payment_date IS NOT NULL
OR ld.return_date IS NOT NULL
DO
SET v_memb_id = active_members.memb_id;
SET v_payment_date = active_members.payment_date;
UPDATE member SET memb_status = 'Active' WHERE memb_id =
v_memb_id;
END FOR;
END

-- view book that is in pending reservation status 
CREATE VIEW bookStatus AS
(SELECT bookdetail.bookdetail_id, book.book_title
FROM book, bookdetail, reservation
WHERE bookdetail.book_id = book.book_id
AND bookdetail.bookdetail_id = reservation.bookdetail_id
AND reservation.reserve_status = 'Pending')

-- display total fine amount and unsettled fine amount of each member
SELECT
m.memb_id,
m.memb_name,
COALESCE(SUM(f.fine_amt), 0) AS total_fine_amt,
COALESCE((SELECT SUM(fine_amt) FROM fine WHERE payment_date IS
NULL AND loandetail_id IN (SELECT loandetail_id FROM loandetail WHERE
loan_id IN (SELECT loan_id FROM loan WHERE memb_id = m.memb_id))), 0)
AS total_unpaid_fine_amt
FROM member m
LEFT JOIN loan l ON m.memb_id = l.memb_id
LEFT JOIN loandetail ld ON l.loan_id = ld.loan_id
LEFT JOIN fine f ON ld.loandetail_id = f.loandetail_id
GROUP BY m.memb_id, m.memb_name

-- insert multiple barcodes into bookdetail table based on the book_amt in book table
CREATE PROCEDURE insert_bookdetail(IN book_id VARCHAR(5), IN book_amt
SMALLINT)
BEGIN
DECLARE i INT DEFAULT 1;
DECLARE temp_barcode VARCHAR(10);
DECLARE barcode_exists INT;
WHILE i <= book_amt DO
SET temp_barcode = LPAD(VARCHAR(INTEGER(RAND() * 100000000)),
8, '0');
SET barcode_exists = (SELECT COUNT(*) FROM bookdetail WHERE
barcode = temp_barcode);
WHILE barcode_exists > 0 DO
SET temp_barcode = LPAD(VARCHAR(INTEGER(RAND() *
100000000)), 8, '0');
SET barcode_exists = (SELECT COUNT(*) FROM bookdetail
WHERE barcode = temp_barcode);
END WHILE;
INSERT INTO bookdetail (book_id, barcode) VALUES (book_id,
temp_barcode);
SET i = i + 1;
END WHILE;
END

-- automated insertion of fine records
CREATE PROCEDURE calculateFine()
LANGUAGE SQL
BEGIN
DECLARE v_loandetail_id VARCHAR(5);
DECLARE v_loan_days INT;
DECLARE v_fine_amt DECIMAL(5,2);
DECLARE v_loan_period INT;
DECLARE v_fine_date DATE;
DECLARE c CURSOR FOR
SELECT ld.loandetail_id, DAYS(CURRENT DATE) -
DAYS(l.loan_date), t.loan_period
FROM loandetail ld
JOIN loan l ON ld.loan_id = l.loan_id
JOIN bookdetail bd ON ld.bookdetail_id = bd.bookdetail_id
JOIN book b ON b.book_id = bd.book_id
JOIN colortag t ON t.tag_id = b.tag_id
WHERE ld.return_date IS NULL;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_loandetail_id =
NULL;
OPEN c;
fetch_loop: LOOP
FETCH c INTO v_loandetail_id, v_days_fine, v_loan_period;
IF v_loandetail_id IS NULL THEN
LEAVE fetch_loop;
END IF;
IF v_loan_days > v_loan_period THEN
SET v_fine_amt = (v_loan_days - v_loan_period);
SET v_fine_date = DATE(DAYS((SELECT loan_date FROM loan l
JOIN loandetail ld ON ld.loan_id = l.loan_id WHERE ld.loandetail_id =
v_loandetail_id)) + v_loan_period + 1);
ELSE
SET v_fine_amt = 0;
SET v_fine_date = NULL;
END IF;
MERGE INTO fine f
USING (
SELECT v_loandetail_id, v_fine_date, v_fine_amt
FROM loandetail ld
WHERE ld.loandetail_id = v_loandetail_id
) AS s (loandetail_id, fine_date, fine_amt)
ON f.loandetail_id = s.loandetail_id
WHEN MATCHED THEN
UPDATE SET f.fine_date = s.fine_date, f.fine_amt =
s.fine_amt
WHEN NOT MATCHED THEN
INSERT (loandetail_id, fine_date, fine_amt) VALUES
(s.loandetail_id, s.fine_date, s.fine_amt);
END LOOP fetch_loop;
CLOSE c;
END

-- generate book id based on category
CREATE TRIGGER generate_book_id
AFTER INSERT ON book
REFERENCING NEW AS new
FOR EACH ROW
BEGIN
DECLARE new_cat_id VARCHAR(5);
DECLARE book_count INT;
SELECT cat_id INTO new_cat_id
FROM category
WHERE cat_keyword = (
SELECT cat_keyword
FROM category
WHERE cat_id = new.cat_id
);
SELECT COUNT(*) INTO book_count
FROM book
WHERE cat_id = new_cat_id;
UPDATE book
SET book_id = (SELECT cat_keyword FROM category WHERE cat_id =
new_cat_id) || '' || VARCHAR(book_count),
cat_id = new_cat_id
WHERE book_id = new.book_id;
END
