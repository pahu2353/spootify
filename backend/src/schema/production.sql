DROP DATABASE IF EXISTS TungTung;
CREATE DATABASE TungTung;
USE TungTung;

CREATE TABLE Users (
  uid INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  profile_picture TEXT,
  phone_number VARCHAR(100),
  email VARCHAR(100),
  overall_rating FLOAT DEFAULT NULL,
  CONSTRAINT check_contact CHECK (phone_number IS NOT NULL OR email IS NOT NULL),
  CONSTRAINT check_overall_rating CHECK (overall_rating IS NULL OR (overall_rating >= 1.0 AND overall_rating <= 5.0))
);

CREATE TABLE TaskCategories (
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  category_name VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE Listings (
  listid INT AUTO_INCREMENT PRIMARY KEY,
  listing_name VARCHAR(100) NOT NULL,
  description TEXT,
  capacity INT DEFAULT 1 CHECK (capacity > 0),
  price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
  duration INT NOT NULL CHECK (duration > 0),
  address VARCHAR(255) NOT NULL,  
  longitude DECIMAL(9,6) NOT NULL,
  latitude DECIMAL(9,6) NOT NULL,
  posting_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  deadline TIMESTAMP,
  status ENUM('open', 'taken', 'completed', 'cancelled')
);

CREATE TABLE BelongsTo (
  listid INT,
  category_id INT,
  PRIMARY KEY (listid, category_id),
  FOREIGN KEY (listid) REFERENCES Listings(listid),
  FOREIGN KEY (category_id) REFERENCES TaskCategories(category_id)
);

CREATE TABLE InterestedIn (
  uid INT,
  category_id INT,
  PRIMARY KEY (uid, category_id),
  FOREIGN KEY (uid) REFERENCES Users(uid),
  FOREIGN KEY (category_id) REFERENCES TaskCategories(category_id)
);

CREATE TABLE AssignedTo (
  listid INT,
  uid INT,
  PRIMARY KEY (listid, uid),
  FOREIGN KEY (listid) REFERENCES Listings(listid),
  FOREIGN KEY (uid) REFERENCES Users(uid)
);

CREATE TABLE Posts (
  listid INT,
  uid INT,
  PRIMARY KEY (listid, uid),
  FOREIGN KEY (listid) REFERENCES Listings(listid),
  FOREIGN KEY (uid) REFERENCES Users(uid)
);

CREATE TABLE Reviews (
  listid INT,
  reviewer_uid INT,
  reviewee_uid INT,
  rating INT CHECK (rating BETWEEN 1 AND 5),
  comment TEXT,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (listid) REFERENCES Listings(listid),
  FOREIGN KEY (reviewer_uid) REFERENCES Users(uid),
  FOREIGN KEY (reviewee_uid) REFERENCES Users(uid),
  -- Composite primary key to ensure unique reviews per listing and user pair (review_id removed)
  PRIMARY KEY (listid, reviewer_uid, reviewee_uid), 
  CONSTRAINT check_no_self_review CHECK (reviewer_uid != reviewee_uid),
  UNIQUE unique_review(listid, reviewer_uid, reviewee_uid)
);

DELIMITER $$

-- enforce deadline >= posting_time + duration
CREATE TRIGGER check_deadline_trigger
BEFORE INSERT ON Listings
FOR EACH ROW
BEGIN
  IF NEW.deadline <= DATE_ADD(NEW.posting_time, INTERVAL NEW.duration MINUTE) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Deadline must be after posting_time + duration';
  END IF;
END$$

CREATE TRIGGER check_deadline_trigger_update
BEFORE UPDATE ON Listings
FOR EACH ROW
BEGIN
  IF NEW.deadline <= DATE_ADD(NEW.posting_time, INTERVAL NEW.duration MINUTE) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Deadline must be after posting_time + duration';
  END IF;
END$$


-- prevent self-assignment
CREATE TRIGGER trg_prevent_self_assignment
BEFORE INSERT ON AssignedTo
FOR EACH ROW
BEGIN
  DECLARE listing_owner INT;

  SELECT uid INTO listing_owner
  FROM Posts
  WHERE listid = NEW.listid;

  IF listing_owner = NEW.uid THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'User cannot assign themselves to their own listing';
  END IF;
END$$

-- prevent assignment to closed/taken listings
CREATE TRIGGER trg_prevent_taken_or_closed
BEFORE INSERT ON AssignedTo
FOR EACH ROW
BEGIN
  DECLARE listing_status ENUM('open', 'taken', 'completed', 'cancelled');

  SELECT status INTO listing_status
  FROM Listings
  WHERE listid = NEW.listid;

  IF listing_status != 'open' THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Listing is not open for assignment';
  END IF;
END$$

-- only assigned users can leave reviews
CREATE TRIGGER trg_enforce_assigned_reviewer
BEFORE INSERT ON Reviews
FOR EACH ROW
BEGIN
  DECLARE is_assigned INT;

  SELECT COUNT(*) INTO is_assigned
  FROM AssignedTo
  WHERE listid = NEW.listid AND uid = NEW.reviewer_uid;

  IF is_assigned = 0 THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Only assigned users can leave reviews';
  END IF;
END$$

-- prevent review unless listing is completed
CREATE TRIGGER trg_check_listing_completed
BEFORE INSERT ON Reviews
FOR EACH ROW
BEGIN
  DECLARE listing_status ENUM('open', 'taken', 'completed', 'cancelled');

  SELECT status INTO listing_status
  FROM Listings
  WHERE listid = NEW.listid;

  IF listing_status != 'completed' THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Only completed listings can be reviewed';
  END IF;
END$$

-- update listing status to 'taken' when capacity is reached
CREATE TRIGGER trg_listing_status_taken
AFTER INSERT ON AssignedTo
FOR EACH ROW
BEGIN
  DECLARE current_assignments INT;
  DECLARE max_capacity INT;

  SELECT COUNT(*) INTO current_assignments
  FROM AssignedTo
  WHERE listid = NEW.listid;

  SELECT capacity INTO max_capacity
  FROM Listings
  WHERE listid = NEW.listid;

  IF current_assignments >= max_capacity THEN
    UPDATE Listings
    SET status = 'taken'
    WHERE listid = NEW.listid AND status = 'open';
  END IF;
END$$

-- update overall_rating after inserting a review
CREATE TRIGGER trg_update_overall_rating
AFTER INSERT ON Reviews
FOR EACH ROW
BEGIN
  DECLARE avg_rating FLOAT;

  SELECT AVG(rating) INTO avg_rating
  FROM Reviews
  WHERE reviewee_uid = NEW.reviewee_uid;

  UPDATE Users
  SET overall_rating = avg_rating
  WHERE uid = NEW.reviewee_uid;
END$$


DELIMITER ;


-- Users (start with NULL, trigger will update overall_rating)
INSERT INTO `Users` (`uid`, `name`, `profile_picture`, `phone_number`, `email`, `overall_rating`)
VALUES
(1,  'Amina Hassan',              'https://placekittens.com/300/300', '415-208-3749', 'amina.hassan@gmail.com',            NULL),
(2,  'Diego Álvarez',            'https://placekittens.com/300/300', '628-473-9021', 'diego.alvarez@yahoo.com',           NULL),
(3,  'Mei-Ling Chen',            'https://placekittens.com/300/300', '347-981-2045', 'meiling.chen@hotmail.com',          NULL),
(4,  'Rajesh Kumar',             'https://placekittens.com/300/300', '212-547-3981', 'rajesh.kumar@gmail.com',             NULL),
(5,  'Ngozi Okafor',            'https://placekittens.com/300/300', '773-290-5012', 'ngozi.okafor@yahoo.com',            NULL),
(6,  'Olga Petrov',             'https://placekittens.com/300/300', '305-671-8320', 'olga.petrov@gmail.com',              NULL),
(7,  'José Santos',             'https://placekittens.com/300/300', '213-940-6721', 'jose.santos@hotmail.com',            NULL),
(8,  'Aisha Al-Farouq',         'https://placekittens.com/300/300', '415-823-9087', 'aisha.farouq@gmail.com',             NULL),
(9,  'Yuki Tanaka',             'https://placekittens.com/300/300', '619-387-1450', 'yuki.tanaka@yahoo.com',              NULL),
(10, 'Kwame Mensah',            'https://placekittens.com/300/300', '510-297-6834', 'kwame.mensah@gmail.com',             NULL),
(11, 'Lucía Gómez',             'https://placekittens.com/300/300', '347-592-1083', 'lucia.gomez@hotmail.com',            NULL),
(12, 'Hiroshi Nakamura',        'https://placekittens.com/300/300', '718-205-3904', 'hiroshi.nakamura@gmail.com',         NULL),
(13, 'Fatima Zahra',            'https://placekittens.com/300/300', '213-578-9021', 'fatima.zahra@yahoo.com',             NULL),
(14, 'Mateo Fernández',         'https://placekittens.com/300/300', '408-325-7104', 'mateo.fernandez@gmail.com',          NULL),
(15, 'Phuong Nguyen',           'https://placekittens.com/300/300', '408-789-2345', 'phuong.nguyen@hotmail.com',          NULL),
(16, 'Ivan Morozov',            'https://placekittens.com/300/300', '415-382-6704', 'ivan.morozov@gmail.com',             NULL),
(17, 'Safiya Mohammed',         'https://placekittens.com/300/300', '202-457-1938', 'safiya.mohammed@yahoo.com',          NULL),
(18, 'Arnav Patel',             'https://placekittens.com/300/300', '312-574-8392', 'arnav.patel@gmail.com',              NULL),
(19, 'Anika Sinha',             'https://placekittens.com/300/300', '415-673-2019', 'anika.sinha@hotmail.com',            NULL),
(20, 'Carlos Mendez',           'https://placekittens.com/300/300', '213-847-5092', 'carlos.mendez@gmail.com',            NULL),
(21, 'Aaliyah Johnson',         'https://placekittens.com/300/300', '323-905-7612', 'aaliyah.johnson@yahoo.com',          NULL),
(22, 'Sven Lund',               'https://placekittens.com/300/300', '415-947-3281', 'sven.lund@hotmail.com',              NULL),
(23, 'Leila Haddad',            'https://placekittens.com/300/300', '646-830-2741', 'leila.haddad@gmail.com',             NULL),
(24, 'Thiago Silva',            'https://placekittens.com/300/300', '213-947-5610', 'thiago.silva@yahoo.com',             NULL),
(25, 'Keisha Brown',            'https://placekittens.com/300/300', '415-728-3402', 'keisha.brown@gmail.com',             NULL),
(26, 'Mikhail Ivanov',          'https://placekittens.com/300/300', '408-681-2930', 'mikhail.ivanov@hotmail.com',         NULL),
(27, 'Anwar Khan',              'https://placekittens.com/300/300', '415-926-3785', 'anwar.khan@gmail.com',               NULL),
(28, 'Sofia Rossi',             'https://placekittens.com/300/300', '213-580-4972', 'sofia.rossi@yahoo.com',              NULL),
(29, 'Jin Woo',                 'https://placekittens.com/300/300', '415-382-7490', 'jin.woo@gmail.com',                   NULL),
(30, 'Nadia Petrova',           'https://placekittens.com/300/300', '408-927-1038', 'nadia.petrova@hotmail.com',          NULL),
(31, 'Miguel Torres',           'https://placekittens.com/300/300', '213-507-8192', 'miguel.torres@gmail.com',            NULL),
(32, 'Chandni Desai',           'https://placekittens.com/300/300', '415-637-8204', 'chandni.desai@yahoo.com',            NULL),
(33, 'Omar Farouk',             'https://placekittens.com/300/300', '415-934-2710', 'omar.farouk@gmail.com',              NULL),
(34, 'Aiko Suzuki',             'https://placekittens.com/300/300', '415-895-2037', 'aiko.suzuki@hotmail.com',            NULL),
(35, 'Darnell Williams',        'https://placekittens.com/300/300', '510-927-3840', 'darnell.williams@gmail.com',         NULL),
(36, 'Yara Haddad',             'https://placekittens.com/300/300', '213-584-9027', 'yara.haddad@yahoo.com',              NULL),
(37, 'Carlos Eduardo',          'https://placekittens.com/300/300', '408-692-3475', 'carlos.eduardo@gmail.com',           NULL),
(38, 'Mai Tran',                'https://placekittens.com/300/300', '415-938-2715', 'mai.tran@hotmail.com',               NULL),
(39, 'Sibusiso Dlamini',        'https://placekittens.com/300/300', '415-672-9035', 'sibusiso.dlamini@gmail.com',         NULL),
(40, 'Elif Yılmaz',             'https://placekittens.com/300/300', '510-927-4830', 'elif.yilmaz@yahoo.com',              NULL),
(41, 'Mateja Novak',            'https://placekittens.com/300/300', '415-837-4592', 'mateja.novak@gmail.com',             NULL),
(42, 'Yara Santos',             'https://placekittens.com/300/300', '213-947-5060', 'yara.santos@hotmail.com',            NULL),
(43, 'Kwabena Agyapong',        'https://placekittens.com/300/300', '415-927-3108', 'kwabena.agyapong@gmail.com',         NULL),
(44, 'Sakura Ito',              'https://placekittens.com/300/300', '408-627-3901', 'sakura.ito@yahoo.com',               NULL),
(45, 'Amara Silva',             'https://placekittens.com/300/300', '415-682-7390', 'amara.silva@gmail.com',              NULL),
(46, 'Hasan Öztürk',            'https://placekittens.com/300/300', '415-892-3701', 'hasan.ozturk@hotmail.com',           NULL),
(47, 'Priya Sharma',            'https://placekittens.com/300/300', '213-584-0927', 'priya.sharma@gmail.com',             NULL),
(48, 'Tejas Patel',             'https://placekittens.com/300/300', '415-927-4832', 'tejas.patel@yahoo.com',              NULL),
(49, 'Mariana Silva',           'https://placekittens.com/300/300', '408-692-8350', 'mariana.silva@hotmail.com',          NULL),
(50, 'Diego Rivera',            'https://placekittens.com/300/300', '415-925-7381', 'diego.rivera@gmail.com',             NULL),
(51, 'Sana Khan',               'https://placekittens.com/300/300', '415-610-4739', 'sana.khan@yahoo.com',                 NULL),
(52, 'Jean-Luc Mbemba',          'https://placekittens.com/300/300', '415-927-4833', 'jeanluc.mbemba@gmail.com',           NULL),
(53, 'Keiko Matsumoto',         'https://placekittens.com/300/300', '408-627-4902', 'keiko.matsumoto@hotmail.com',         NULL),
(54, 'Tariq Aziz',              'https://placekittens.com/300/300', '415-837-9027', 'tariq.aziz@gmail.com',               NULL),
(55, 'Marisol Cortez',          'https://placekittens.com/300/300', '213-947-6150', 'marisol.cortez@gmail.com',           NULL),
(56, 'Hassan Jafari',           'https://placekittens.com/300/300', '415-682-9273', 'hassan.jafari@yahoo.com',            NULL),
(57, 'Cheng Wei',               'https://placekittens.com/300/300', '408-627-3456', 'cheng.wei@hotmail.com',              NULL),
(58, 'Zahra Alami',             'https://placekittens.com/300/300', '415-927-4834', 'zahra.alami@gmail.com',              NULL),
(59, 'Jamal Robinson',          'https://placekittens.com/300/300', '510-927-4835', 'jamal.robinson@hotmail.com',         NULL),
(60, 'Fumiko Tanaka',           'https://placekittens.com/300/300', '415-837-5927', 'fumiko.tanaka@gmail.com',           NULL),
(61, 'Ravi Singh',              'https://placekittens.com/300/300', '408-827-3940', 'ravi.singh@yahoo.com',                NULL),
(62, 'Luciana Costa',           'https://placekittens.com/300/300', '213-947-3821', 'luciana.costa@gmail.com',            NULL),
(63, 'Ahmed Al-Sharif',         'https://placekittens.com/300/300', '415-927-4836', 'ahmed.sharif@hotmail.com',           NULL),
(64, 'Svetlana Orlova',         'https://placekittens.com/300/300', '408-627-4930', 'svetlana.orlova@gmail.com',          NULL),
(65, 'Marwan Haddad',           'https://placekittens.com/300/300', '415-837-9047', 'marwan.haddad@yahoo.com',             NULL),
(66, 'Keiran Murphy',           'https://placekittens.com/300/300', '415-927-4837', 'keiran.murphy@gmail.com',            NULL),
(67, 'Anjali Mehta',            'https://placekittens.com/300/300', '408-627-4920', 'anjali.mehta@hotmail.com',           NULL),
(68, 'Mohamad Youssef',         'https://placekittens.com/300/300', '213-947-6151', 'mohamad.youssef@gmail.com',          NULL),
(69, 'Camila Rojas',            'https://placekittens.com/300/300', '415-682-7391', 'camila.rojas@yahoo.com',              NULL),
(70, 'Kai Müller',              'https://placekittens.com/300/300', '408-627-4900', 'kai.muller@hotmail.com',             NULL),
(71, 'Nneka Okeke',             'https://placekittens.com/300/300', '510-927-4838', 'nneka.okeke@gmail.com',              NULL),
(72, 'Lin Wei',                 'https://placekittens.com/300/300', '415-837-9048', 'lin.wei@yahoo.com',                   NULL),
(73, 'Osman Kaya',              'https://placekittens.com/300/300', '415-927-4839', 'osman.kaya@hotmail.com',             NULL),
(74, 'Eliana Martínez',         'https://placekittens.com/300/300', '213-947-5061', 'eliana.martinez@gmail.com',          NULL),
(75, 'Sipho Ndlovu',            'https://placekittens.com/300/300', '415-682-9290', 'sipho.ndlovu@yahoo.com',             NULL),
(76, 'Hye-Jin Kim',             'https://placekittens.com/300/300', '408-627-4931', 'hyejin.kim@gmail.com',                NULL),
(77, 'Radhika Iyer',            'https://placekittens.com/300/300', '415-837-5930', 'radhika.iyer@hotmail.com',           NULL),
(78, 'Jorge Herrera',           'https://placekittens.com/300/300', '213-947-7282', 'jorge.herrera@yahoo.com',             NULL),
(79, 'Tunde Adebayo',           'https://placekittens.com/300/300', '510-927-4832', 'tunde.adebayo@gmail.com',             NULL),
(80, 'Chang Liu',               'https://placekittens.com/300/300', '415-682-7392', 'chang.liu@hotmail.com',              NULL),
(81, 'Adebisi Oluwole',         'https://placekittens.com/300/300', '408-627-4901', 'adebisi.oluwole@yahoo.com',           NULL),
(82, 'Kamila Nowak',            'https://placekittens.com/300/300', '415-927-4831', 'kamila.nowak@gmail.com',             NULL),
(83, 'Marcos Gutierrez',        'https://placekittens.com/300/300', '213-947-5062', 'marcos.gutierrez@hotmail.com',        NULL),
(84, 'Fatou Diop',              'https://placekittens.com/300/300', '510-927-4830', 'fatou.diop@yahoo.com',               NULL),
(85, 'Yasemin Demir',            'https://placekittens.com/300/300', '415-682-7393', 'yasemin.demir@gmail.com',            NULL),
(86, 'Nuria Serrano',           'https://placekittens.com/300/300', '408-627-4932', 'nuria.serrano@hotmail.com',           NULL),
(87, 'Aminatou Diallo',         'https://placekittens.com/300/300', '415-837-9050', 'aminatou.diallo@gmail.com',          NULL),
(88, 'Evgeni Petrov',           'https://placekittens.com/300/300', '213-947-7281', 'evgeni.petrov@yahoo.com',             NULL),
(89, 'Noor Al-Sayed',           'https://placekittens.com/300/300', '510-927-4831', 'noor.alsayed@hotmail.com',           NULL),
(90, 'Chike Obi',               'https://placekittens.com/300/300', '415-682-7394', 'chike.obi@gmail.com',                 NULL),
(91, 'Cristina Pérez',          'https://placekittens.com/300/300', '408-627-4933', 'cristina.perez@yahoo.com',           NULL),
(92, 'Min-Joon Park',           'https://placekittens.com/300/300', '415-837-5931', 'minjoon.park@gmail.com',              NULL),
(93, 'Amélie Dubois',           'https://placekittens.com/300/300', '213-947-5063', 'amelie.dubois@hotmail.com',           NULL),
(94, 'Ibrahim Abdi',            'https://placekittens.com/300/300', '510-927-4834', 'ibrahim.abdi@yahoo.com',              NULL),
(95, 'Isha Patel',              'https://placekittens.com/300/300', '415-682-7395', 'isha.patel@gmail.com',               NULL),
(96, 'Gabriel Santos',          'https://placekittens.com/300/300', '408-627-4903', 'gabriel.santos@hotmail.com',          NULL),
(97, 'Sebastian Klein',         'https://placekittens.com/300/300', '415-927-4830', 'sebastian.klein@gmail.com',           NULL),
(98, 'Karima Nasser',           'https://placekittens.com/300/300', '213-947-7283', 'karima.nasser@yahoo.com',            NULL),
(99, 'Oluwaseun Adeyemi',       'https://placekittens.com/300/300', '510-927-4836', 'oluwaseun.adeyemi@hotmail.com',       NULL),
(100,'Leena Sharma',            'https://placekittens.com/300/300', '415-682-7396', 'leena.sharma@gmail.com',             NULL);

-- Task Categories
INSERT INTO TaskCategories (category_name) VALUES
    ('Gardening'),
    ('Tutoring'),
    ('Plumbing'),
    ('Moving'),
    ('Cleaning'),
    ('Electrical'),
    ('Babysitting'),
    ('Delivery'),
    ('Painting'),
    ('Cooking'),
    ('Shopping'),
    ('Laundry'),
    ('Assembly'),
    ('Petcare'),
    ('Tech');

-- Listings 1–20
INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (1, 'Backyard Gardening Assistance', 'I need help trimming hedges and de-weeding.', 1, 25.00, 120, '123 Maple St, Toronto, ON, Canada', -79.3832, 43.6532, '2026-06-18 08:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (2, 'Math Tutoring Needed', 'Grade 10 student struggles with algebra.', 1, 35.00, 90, '456 Elm Rd, London, UK', -0.1278, 51.5074, '2026-06-20 17:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (3, 'Kitchen Sink Leak', 'Plumber help required ASAP.', 1, 80.00, 60, '789 Oak Dr, Melbourne, Australia', 144.9631, -37.8136, '2026-06-18 12:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (4, 'Piano Moving Request', 'Need help moving upright piano.', 4, 150.00, 180, '12 Beethoven Ave, Vienna, Austria', 16.3738, 48.2082, '2026-07-01 10:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (5, 'Home Deep Cleaning', 'Bathrooms and kitchen need attention.', 2, 120.00, 180, '34 Rue de la Paix, Paris, France', 2.3522, 48.8566, '2026-06-20 09:30:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (6, 'Electrical Outlet Install', 'Need extra plug in living room.', 1, 60.00, 90, '56 Green St, Auckland, NZ', 174.7633, -36.8485, '2026-06-25 14:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (7, 'Evening Babysitting', 'Looking after 2 kids for 4 hours.', 2, 50.00, 240, '78 Sunset Blvd, Los Angeles, CA, USA', -118.2437, 34.0522, '2026-06-21 20:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (8, 'Grocery Delivery', 'Pick up and deliver my weekly shopping.', 1, 30.00, 60, '90 Queen St, Auckland, NZ', 174.7633, -36.8485, '2026-06-22 18:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (9, 'Living Room Painting', 'Primer and one top coat.', 2, 200.00, 300, '123 King St, Sydney, Australia', 151.2093, -33.8688, '2026-06-30 09:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (10, 'Home Chef Needed', 'Prepare dinner for family of 5.', 1, 100.00, 180, '456 Ranch Rd, Austin, TX, USA', -97.7431, 30.2672, '2026-06-21 17:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (11, 'Weekly Laundry Service', 'Wash and fold clothes.', 1, 40.00, 120, '12 Elm St, Dublin, Ireland', -6.2603, 53.3498, '2026-06-28 11:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (12, 'Ikea Furniture Assembly', 'Assemble bookcase and table.', 1, 70.00, 180, '78 Avenida Paulista, São Paulo, Brazil', -46.6333, -23.5505, '2026-06-23 13:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (13, 'Cat Sitting', 'Feed and play with my cat for 3 evenings.', 1, 45.00, 180, '34 شارع الملك فهد, Riyadh, Saudi Arabia', 46.6753, 24.7136, '2026-06-29 19:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (14, 'Laptop Setup', 'Need help installing software and updates.', 1, 60.00, 90, '90 Bahnhofstrasse, Zurich, Switzerland', 8.5417, 47.3769, '2026-06-19 11:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (15, 'Garden Watering', 'Away next week, need watering service.', 1, 30.00, 30, '345 Maple Rd, Vancouver, BC, Canada', -123.1207, 49.2827, '2026-06-24 08:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (16, 'Spanish Tutoring', 'Intermediate level conversation practice.', 1, 40.00, 60, 'City Center, Madrid, Spain', -3.7038, 40.4168, '2026-06-23 15:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (17, 'Bathroom Plumbing Repair', 'Clogged drain needs fixing.', 1, 90.00, 90, '22 Queen St, Toronto, ON, Canada', -79.3832, 43.6532, '2026-06-23 14:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (18, 'Assist with House Move', '2-bedroom apartment move.', 3, 200.00, 240, '8 Avenida da Liberdade, Lisbon, Portugal', -9.1393, 38.7223, '2026-06-26 12:00:00', 'cancelled');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (19, 'One-time Deep Cleaning', 'After party mess cleanup.', 2, 150.00, 240, '56 Queen St, Auckland, NZ', 174.7633, -36.8485, '2026-07-02 09:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (20, 'Install Smart Light Switch', 'Need smart switch wired in.', 1, 75.00, 120, '100 Broadway, New York, NY, USA', -74.0060, 40.7128, '2026-06-24 10:00:00', 'open');

-- Listings 21–40
INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (21, 'Dog Walking Needed', 'Walk my energetic golden retriever daily.', 1, 25.00, 30, '234 Main St, Seattle, WA, USA', -122.3321, 47.6062, '2026-06-20 07:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (22, 'Tutoring: High School Physics', 'Help understanding kinematics and forces.', 1, 40.00, 90, '567 Oak Lane, Chicago, IL, USA', -87.6298, 41.8781, '2026-06-27 15:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (23, 'Fix Leaky Faucet', 'Kitchen faucet dripping constantly.', 1, 70.00, 60, '890 Pine Rd, Vancouver, BC, Canada', -123.1207, 49.2827, '2026-06-23 11:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (24, 'Help Moving Boxes', 'Assist with packing and moving boxes.', 3, 120.00, 180, '12 Cherry St, Dublin, Ireland', -6.2603, 53.3498, '2026-07-05 10:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (25, 'Interior Wall Painting', 'Paint two bedrooms.', 2, 180.00, 240, '45 Park Ave, New York, NY, USA', -74.0060, 40.7128, '2026-06-27 13:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (26, 'Cooking Help: Birthday Party', 'Prepare finger foods for 20 guests.', 1, 120.00, 240, '789 Maple Dr, Toronto, ON, Canada', -79.3832, 43.6532, '2026-06-21 18:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (27, 'Weekly Grocery Shopping', 'Buy groceries using my list.', 1, 35.00, 90, '99 King St, Sydney, Australia', 151.2093, -33.8688, '2026-06-24 16:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (28, 'Laundry Pickup and Delivery', 'Pickup clothes, wash and return.', 1, 50.00, 120, '67 Queen St, Auckland, NZ', 174.7633, -36.8485, '2026-06-26 12:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (29, 'Assemble Office Desk', 'Assemble IKEA desk.', 1, 80.00, 150, '123 Market St, San Francisco, CA, USA', -122.4194, 37.7749, '2026-06-28 11:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (30, 'Pet Sitting for Cat', 'Feed and clean litter box.', 1, 40.00, 180, '321 Elm St, Chicago, IL, USA', -87.6298, 41.8781, '2026-06-30 20:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (31, 'Help with Computer Setup', 'Install software and printers.', 1, 55.00, 120, '456 Tech Rd, Berlin, Germany', 13.4050, 52.5200, '2026-06-22 14:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (32, 'Plant Care While Away', 'Water and trim indoor plants.', 1, 30.00, 60, '123 Garden Lane, Brisbane, Australia', 153.0251, -27.4698, '2026-06-25 09:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (33, 'French Language Tutoring', 'Conversational French help.', 1, 45.00, 90, '23 Rue Lafayette, Paris, France', 2.3522, 48.8566, '2026-06-23 11:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (34, 'Repair Toilet Flush', 'Handle broken flush mechanism.', 1, 85.00, 60, '78 Pine St, Auckland, NZ', 174.7633, -36.8485, '2026-06-22 13:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (35, 'Help Packing for Move', 'Pack fragile items carefully.', 2, 110.00, 180, '12 Elmwood Dr, Chicago, IL, USA', -87.6298, 41.8781, '2026-06-27 12:00:00', 'cancelled');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (36, 'Deep Clean After Renovation', 'Dust and polish all rooms.', 3, 175.00, 240, '56 Green Rd, London, UK', -0.1278, 51.5074, '2026-07-01 10:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (37, 'Install Ceiling Fan', 'Replace old fan with new model.', 1, 95.00, 120, '90 Hill St, Melbourne, Australia', 144.9631, -37.8136, '2026-06-25 14:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (38, 'Babysitting for Evening', 'Care for 3-year-old for 5 hours.', 1, 55.00, 300, '67 Broadway, New York, NY, USA', -74.0060, 40.7128, '2026-06-20 17:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (39, 'Deliver Package', 'Pick up and deliver a small parcel.', 1, 25.00, 60, '45 Main St, Vancouver, BC, Canada', -123.1207, 49.2827, '2026-06-21 13:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (40, 'Room Painting', 'Paint guest room with light blue.', 1, 150.00, 240, '89 Elm St, Dublin, Ireland', -6.2603, 53.3498, '2026-06-28 09:00:00', 'open');

-- Listings 41–60
INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (41, 'Prepare Weekly Meals', 'Cook and package meals for family of 4.', 1, 130.00, 240, '123 West St, Toronto, ON, Canada', -79.3832, 43.6532, '2026-06-26 14:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (42, 'Grocery Shopping Help', 'Shop with list, focus on organic products.', 1, 40.00, 90, '456 King St, Sydney, Australia', 151.2093, -33.8688, '2026-06-23 18:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (43, 'Clothes Laundry Service', 'Wash, dry, and fold.', 1, 45.00, 120, '67 Queen St, Auckland, NZ', 174.7633, -36.8485, '2026-06-26 11:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (44, 'Assemble Dining Chairs', 'Assemble 4 dining chairs.', 1, 60.00, 90, '12 Park Ave, New York, NY, USA', -74.0060, 40.7128, '2026-06-27 10:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (45, 'Pet Care: Dog Sitting', 'Look after dog for weekend.', 1, 50.00, 180, '89 Oak St, London, UK', -0.1278, 51.5074, '2026-06-24 15:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (46, 'Tech Support', 'Setup new router and Wi-Fi.', 1, 70.00, 90, '34 Elm Rd, Berlin, Germany', 13.4050, 52.5200, '2026-06-21 14:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (47, 'Lawn Mowing', 'Mow front and backyard.', 1, 35.00, 60, '56 Maple St, Vancouver, BC, Canada', -123.1207, 49.2827, '2026-06-22 11:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (48, 'Tutoring: Chemistry', 'Help with high school chemistry homework.', 1, 40.00, 90, '123 College Rd, Dublin, Ireland', -6.2603, 53.3498, '2026-06-30 16:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (49, 'Fix Broken Door Handle', 'Replace or repair door handle.', 1, 60.00, 60, '78 Pine St, Melbourne, Australia', 144.9631, -37.8136, '2026-06-22 12:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (50, 'Help Moving Furniture', 'Assist moving sofa and bed.', 3, 140.00, 180, '45 Elm St, Toronto, ON, Canada', -79.3832, 43.6532, '2026-07-03 10:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (51, 'Painting Fences', 'Paint wooden fence white.', 2, 120.00, 240, '90 Queen St, Auckland, NZ', 174.7633, -36.8485, '2026-06-26 13:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (52, 'Cook Dinner for Event', 'Prepare meal for 10 people.', 1, 110.00, 180, '12 Oak Rd, London, UK', -0.1278, 51.5074, '2026-06-22 19:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (53, 'Grocery Shopping Assistance', 'Shop for fresh fruits and vegetables.', 1, 30.00, 60, '56 King St, Sydney, Australia', 151.2093, -33.8688, '2026-06-23 10:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (54, 'Laundry Service Pickup', 'Pickup and drop-off service.', 1, 40.00, 120, '34 Queen St, Dublin, Ireland', -6.2603, 53.3498, '2026-06-29 12:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (55, 'Assemble Bookshelf', 'Assemble large wooden bookshelf.', 1, 90.00, 150, '123 Elm Rd, New York, NY, USA', -74.0060, 40.7128, '2026-06-27 14:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (56, 'Pet Sitting for Rabbits', 'Feed and clean cages.', 1, 40.00, 180, '89 Main St, Berlin, Germany', 13.4050, 52.5200, '2026-06-30 18:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (57, 'Help Setting up Printer', 'Connect and configure printer.', 1, 60.00, 90, '45 Tech Blvd, San Francisco, CA, USA', -122.4194, 37.7749, '2026-06-23 09:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (58, 'Indoor Plant Care', 'Water and fertilize plants weekly.', 1, 30.00, 60, '78 Garden St, Paris, France', 2.3522, 48.8566, '2026-06-25 09:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (59, 'Italian Language Tutoring', 'Beginner Italian lessons.', 1, 45.00, 90, '23 Via Roma, Rome, Italy', 12.4964, 41.9028, '2026-06-26 10:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (60, 'Fix Clogged Shower Drain', 'Slow draining shower.', 1, 80.00, 60, '12 Pine St, Melbourne, Australia', 144.9631, -37.8136, '2026-06-22 13:00:00', 'taken');

-- Listings 61–80
INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (61, 'Help Packing for Move', 'Pack fragile items carefully.', 2, 110.00, 180, '12 Elmwood Dr, Chicago, IL, USA', -87.6298, 41.8781, '2026-06-26 15:00:00', 'cancelled');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (62, 'Deep Clean After Renovation', 'Dust and polish all rooms.', 3, 175.00, 240, '56 Green Rd, London, UK', -0.1278, 51.5074, '2026-07-01 10:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (63, 'Install Ceiling Fan', 'Replace old fan with new model.', 1, 95.00, 120, '90 Hill St, Melbourne, Australia', 144.9631, -37.8136, '2026-06-23 12:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (64, 'Babysitting for Evening', 'Care for 3-year-old for 5 hours.', 1, 55.00, 300, '67 Broadway, New York, NY, USA', -74.0060, 40.7128, '2026-06-20 17:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (65, 'Deliver Package', 'Pick up and deliver a small parcel.', 1, 25.00, 60, '45 Main St, Vancouver, BC, Canada', -123.1207, 49.2827, '2026-06-21 11:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (66, 'Room Painting', 'Paint guest room with light blue.', 1, 150.00, 240, '89 Elm St, Dublin, Ireland', -6.2603, 53.3498, '2026-06-28 09:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (67, 'Prepare Weekly Family Meals', 'Cook and package meals for family of 4.', 1, 125.00, 240, '123 West St, Toronto, ON, Canada', -79.3832, 43.6532, '2026-06-26 16:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (68, 'Grocery Shopping Help', 'Buy groceries using my list.', 1, 35.00, 90, '99 King St, Sydney, Australia', 151.2093, -33.8688, '2026-06-24 11:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (69, 'Laundry Pickup and Delivery', 'Pickup clothes, wash and return.', 1, 50.00, 120, '67 Queen St, Auckland, NZ', 174.7633, -36.8485, '2026-06-26 12:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (70, 'Assemble Office Desk', 'Assemble IKEA desk.', 1, 80.00, 150, '123 Market St, San Francisco, CA, USA', -122.4194, 37.7749, '2026-06-27 13:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (71, 'Pet Sitting for Cat', 'Feed and clean litter box.', 1, 40.00, 180, '321 Elm St, Chicago, IL, USA', -87.6298, 41.8781, '2026-06-30 20:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (72, 'Help with Computer Setup', 'Install software and printers.', 1, 55.00, 120, '456 Tech Rd, Berlin, Germany', 13.4050, 52.5200, '2026-06-24 15:00:00', 'completed');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (73, 'Plant Care While Away', 'Water and trim indoor plants.', 1, 30.00, 60, '123 Garden Lane, Brisbane, Australia', 153.0251, -27.4698, '2026-06-25 09:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (74, 'French Language Tutoring', 'Conversational French help.', 1, 45.00, 90, '23 Rue Lafayette, Paris, France', 2.3522, 48.8566, '2026-06-27 14:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (75, 'Repair Toilet Flush', 'Handle broken flush mechanism.', 1, 85.00, 60, '78 Pine St, Auckland, NZ', 174.7633, -36.8485, '2026-06-22 13:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (76, 'Help Packing Boxes', 'Pack fragile kitchenware.', 2, 100.00, 180, '56 Elm St, Toronto, ON, Canada', -79.3832, 43.6532, '2026-06-26 17:00:00', 'cancelled');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (77, 'Deep Clean Post Renovation', 'Dust and sanitize all surfaces.', 3, 160.00, 240, '90 Green Rd, London, UK', -0.1278, 51.5074, '2026-07-01 09:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (78, 'Install Wall Mounted TV', 'Mount and connect TV.', 1, 95.00, 120, '67 Broadway, New York, NY, USA', -74.0060, 40.7128, '2026-06-23 16:00:00', 'open');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (79, 'Babysitting Weekend', 'Care for 2 children, ages 5 and 7.', 1, 60.00, 480, '34 Sunset Blvd, Los Angeles, CA, USA', -118.2437, 34.0522, '2026-06-20 16:00:00', 'taken');

INSERT INTO Listings (listid, listing_name, description, capacity, price, duration, address, longitude, latitude, deadline, status)
VALUES (80, 'Deliver Documents', 'Urgent delivery downtown.', 1, 20.00, 30, '45 Queen St, Vancouver, BC, Canada', -123.1207, 49.2827, '2026-06-21 10:00:00', 'open');



INSERT INTO BelongsTo (listid, category_id) VALUES
-- 1-20
(1, 1),    -- Backyard Gardening Assistance -> Gardening
(2, 2),    -- Math Tutoring Needed -> Tutoring
(3, 3),    -- Kitchen Sink Leak -> Plumbing
(4, 4),    -- Piano Moving Request -> Moving
(5, 5),    -- Home Deep Cleaning -> Cleaning
(6, 6),    -- Electrical Outlet Install -> Electrical
(7, 7),    -- Evening Babysitting -> Babysitting
(8, 8),    -- Grocery Delivery -> Delivery
(9, 9),    -- Living Room Painting -> Painting
(10, 10),  -- Home Chef Needed -> Cooking
(11, 12),  -- Weekly Laundry Service -> Laundry
(12, 13),  -- Ikea Furniture Assembly -> Assembly
(13, 14),  -- Cat Sitting -> Petcare
(14, 15),  -- Laptop Setup -> Tech
(15, 1),   -- Garden Watering -> Gardening
(16, 2),   -- Spanish Tutoring -> Tutoring
(17, 3),   -- Bathroom Plumbing Repair -> Plumbing
(18, 4),   -- Assist with House Move -> Moving
(19, 5),   -- One-time Deep Cleaning -> Cleaning
(20, 6),   -- Install Smart Light Switch -> Electrical

-- 21-40
(21, 14),  -- Dog Walking Needed -> Petcare
(22, 2),   -- Tutoring: High School Physics -> Tutoring
(23, 3),   -- Fix Leaky Faucet -> Plumbing
(24, 4),   -- Help Moving Boxes -> Moving
(25, 9),   -- Interior Wall Painting -> Painting
(26, 10),  -- Cooking Help: Birthday Party -> Cooking
(27, 11),  -- Weekly Grocery Shopping -> Shopping
(28, 12),  -- Laundry Pickup and Delivery -> Laundry
(29, 13),  -- Assemble Office Desk -> Assembly
(30, 14),  -- Pet Sitting for Cat -> Petcare
(31, 15),  -- Help with Computer Setup -> Tech
(32, 14),  -- Plant Care While Away -> Petcare
(33, 2),   -- French Language Tutoring -> Tutoring
(34, 3),   -- Repair Toilet Flush -> Plumbing
(35, 4),   -- Help Packing for Move -> Moving
(36, 5),   -- Deep Clean After Renovation -> Cleaning
(37, 6),   -- Install Ceiling Fan -> Electrical
(38, 7),   -- Babysitting for Evening -> Babysitting
(39, 8),   -- Deliver Package -> Delivery
(40, 9),   -- Room Painting -> Painting

-- 41-60
(41, 10),  -- Prepare Weekly Meals -> Cooking
(42, 11),  -- Grocery Shopping Help -> Shopping
(43, 12),  -- Clothes Laundry Service -> Laundry
(44, 13),  -- Assemble Dining Chairs -> Assembly
(45, 14),  -- Pet Care: Dog Sitting -> Petcare
(46, 15),  -- Tech Support -> Tech
(47, 1),   -- Lawn Mowing -> Gardening
(48, 2),   -- Tutoring: Chemistry -> Tutoring
(49, 3),   -- Fix Broken Door Handle -> Plumbing
(50, 4),   -- Help Moving Furniture -> Moving
(51, 5),   -- Painting Fences -> Cleaning
(52, 10),  -- Cook Dinner for Event -> Cooking
(53, 11),  -- Grocery Shopping Assistance -> Shopping
(54, 12),  -- Laundry Service Pickup -> Laundry
(55, 13),  -- Assemble Bookshelf -> Assembly
(56, 14),  -- Pet Sitting for Rabbits -> Petcare
(57, 15),  -- Help Setting up Printer -> Tech
(58, 14),  -- Indoor Plant Care -> Petcare
(59, 2),   -- Italian Language Tutoring -> Tutoring
(60, 3),   -- Fix Clogged Shower Drain -> Plumbing

-- 61-80
(61, 4),   -- Help Packing for Move -> Moving
(62, 5),   -- Deep Clean After Renovation -> Cleaning
(63, 6),   -- Install Ceiling Fan -> Electrical
(64, 7),   -- Babysitting for Evening -> Babysitting
(65, 8),   -- Deliver Package -> Delivery
(66, 9),   -- Room Painting -> Painting
(67, 10),  -- Prepare Weekly Family Meals -> Cooking
(68, 11),  -- Grocery Shopping Help -> Shopping
(69, 12),  -- Laundry Pickup and Delivery -> Laundry
(70, 13),  -- Assemble Office Desk -> Assembly
(71, 14),  -- Pet Sitting for Cat -> Petcare
(72, 15),  -- Help with Computer Setup -> Tech
(73, 14),  -- Plant Care While Away -> Petcare
(74, 2),   -- French Language Tutoring -> Tutoring
(75, 3),   -- Repair Toilet Flush -> Plumbing
(76, 13),  -- Help Packing Boxes -> Assembly
(77, 5),   -- Deep Clean Post Renovation -> Cleaning
(78, 15),  -- Install Wall Mounted TV -> Tech
(79, 7),   -- Babysitting Weekend -> Babysitting
(80, 8);   -- Deliver Documents -> Delivery


-- Posts
INSERT INTO Posts (listid, uid) VALUES
(1, 12),
(2, 57),
(3, 23),
(4, 89),
(5, 12),
(6, 42),
(7, 5),
(8, 77),
(9, 30),
(10, 18),
(11, 42),
(12, 94),
(13, 57),
(14, 61),
(15, 2),
(16, 84),
(17, 23),
(18, 99),
(19, 48),
(20, 61),
(21, 5),
(22, 35),
(23, 77),
(24, 6),
(25, 12),
(26, 57),
(27, 23),
(28, 89),
(29, 42),
(30, 5),
(31, 77),
(32, 30),
(33, 18),
(34, 42),
(35, 94),
(36, 57),
(37, 61),
(38, 2),
(39, 84),
(40, 23),
(41, 99),
(42, 48),
(43, 61),
(44, 5),
(45, 35),
(46, 77),
(47, 6),
(48, 12),
(49, 57),
(50, 23),
(51, 89),
(52, 42),
(53, 5),
(54, 77),
(55, 30),
(56, 18),
(57, 42),
(58, 94),
(59, 57),
(60, 61),
(61, 2),
(62, 84),
(63, 23),
(64, 99),
(65, 48),
(66, 61),
(67, 5),
(68, 35),
(69, 77),
(70, 6),
(71, 12),
(72, 57),
(73, 23),
(74, 89),
(75, 42),
(76, 5),
(77, 77),
(78, 30),
(79, 18),
(80, 42);

-- InterestedIn
INSERT INTO InterestedIn (uid, category_id) VALUES
(1, 12),
(1, 5),
(2, 7),
(2, 14),
(2, 2),
(3, 1),
(3, 11),
(3, 15),
(4, 6),
(4, 9),
(5, 8),
(5, 13),
(6, 3),
(6, 7),
(6, 1),
(7, 10),
(7, 4),
(7, 5),
(8, 14),
(9, 12),
(9, 2),
(10, 6),
(10, 11),
(11, 9),
(11, 15),
(12, 3),
(12, 8),
(12, 1),
(13, 5),
(13, 7),
(14, 13),
(15, 2),
(15, 14),
(16, 4),
(16, 10),
(17, 8),
(17, 12),
(18, 1),
(18, 5),
(18, 11),
(19, 3),
(20, 7),
(20, 15),
(21, 2),
(21, 9),
(22, 13),
(23, 4),
(23, 6),
(24, 8),
(24, 12),
(24, 14),
(25, 1),
(25, 10),
(26, 11),
(26, 15),
(27, 3),
(27, 7),
(28, 5),
(28, 9),
(29, 2),
(29, 14),
(30, 4),
(30, 13),
(31, 6),
(31, 8),
(32, 12),
(33, 15),
(33, 1),
(34, 7),
(34, 10),
(35, 2),
(35, 9),
(36, 11),
(37, 14),
(37, 3),
(38, 5),
(38, 8),
(39, 4),
(39, 13),
(40, 6),
(40, 15),
(41, 1),
(41, 12),
(42, 7),
(42, 10),
(43, 2),
(44, 9),
(44, 14),
(45, 3),
(45, 5),
(46, 8),
(46, 11),
(47, 13),
(48, 1),
(48, 6),
(49, 10),
(49, 15),
(50, 4),
(50, 7),
(51, 2),
(51, 14),
(52, 9),
(52, 5),
(53, 11),
(53, 3),
(54, 8),
(54, 13),
(55, 1),
(55, 6),
(56, 10),
(56, 15),
(57, 2),
(57, 7),
(58, 12),
(59, 4),
(59, 9),
(60, 14),
(60, 5),
(61, 11),
(62, 3),
(62, 8),
(63, 13),
(63, 1),
(64, 6),
(64, 10),
(65, 15),
(65, 7),
(66, 2),
(67, 14),
(67, 5),
(68, 11),
(68, 4),
(69, 9),
(69, 13),
(70, 3),
(70, 8),
(71, 1),
(71, 6),
(72, 10),
(72, 15),
(73, 7),
(74, 2),
(74, 14),
(75, 5),
(75, 11),
(76, 4),
(76, 9),
(77, 13),
(77, 1),
(78, 6),
(78, 10),
(79, 15),
(79, 3),
(80, 8),
(80, 12),
(81, 7),
(81, 2),
(82, 14),
(83, 5),
(83, 11),
(84, 1),
(84, 6),
(85, 10),
(85, 15),
(86, 3),
(86, 8),
(87, 13),
(87, 7),
(88, 2),
(88, 14),
(89, 5),
(89, 11),
(90, 4),
(90, 9),
(91, 13),
(91, 1),
(92, 6),
(92, 10),
(93, 15),
(93, 7),
(94, 2),
(94, 14),
(95, 5),
(95, 11),
(96, 3),
(96, 8),
(98, 6),
(98, 10),
(99, 15),
(99, 7),
(100, 2),
(100, 14);


-- Listing 2 (open, capacity=1, owner=57)
-- leave unassigned to keep it open

-- Listing 3 (open, capacity=1, owner=23)
-- leave unassigned to keep it open

-- Listing 4 (open, capacity=4, owner=89)
INSERT INTO AssignedTo (listid, uid) VALUES
(4, 12),
(4, 42);

-- Listing 6 (open, capacity=1, owner=42)
-- leave unassigned to keep it open

-- Listing 9 (open, capacity=2, owner=30)
INSERT INTO AssignedTo (listid, uid) VALUES
(9, 18);

-- Listing 10 (open, capacity=1, owner=18)
-- leave unassigned to keep it open

-- Listing 12 (open, capacity=1, owner=94)
-- leave unassigned to keep it open

-- Listing 13 (open, capacity=1, owner=57)
INSERT INTO AssignedTo (listid, uid) VALUES
(13, 61);

-- Listing 15 (open, capacity=1, owner=2)
-- leave unassigned to keep it open

-- Listing 16 (open, capacity=1, owner=84)
INSERT INTO AssignedTo (listid, uid) VALUES
(16, 23);

-- Listing 19 (open, capacity=2, owner=48)
INSERT INTO AssignedTo (listid, uid) VALUES
(19, 61);

-- Listing 20 (open, capacity=1, owner=61)
-- leave unassigned to keep it open


-- Listing 21 (capacity 1, owner 5) => no assignment to keep open

-- Listing 23 (capacity 1, owner 77)
INSERT INTO AssignedTo (listid, uid) VALUES (23, 42);

-- Listing 24 (capacity 3, owner 6) assign 2 users
INSERT INTO AssignedTo (listid, uid) VALUES
  (24, 12),
  (24, 57);

-- Listing 26 (capacity 1, owner 57) no assignment to keep open

-- Listing 28 (capacity 1, owner 89) no assignment

-- Listing 29 (capacity 1, owner 42) no assignment

-- Listing 32 (capacity 1, owner 30) no assignment

-- Listing 33 (capacity 1, owner 18)
INSERT INTO AssignedTo (listid, uid) VALUES (33, 57);

-- Listing 36 (capacity 3, owner 57) assign 2 users
INSERT INTO AssignedTo (listid, uid) VALUES
  (36, 12),
  (36, 18);

-- Listing 37 (capacity 1, owner 61) no assignment

-- Listing 43 (capacity 1, owner 61) no assignment

-- Listing 44 (capacity 1, owner 5)
INSERT INTO AssignedTo (listid, uid) VALUES (44, 42);

-- Listing 46 (capacity 1, owner 77) no assignment

-- Listing 47 (capacity 1, owner 6) no assignment

-- Listing 49 (capacity 1, owner 57)
INSERT INTO AssignedTo (listid, uid) VALUES (49, 30);

-- Listing 50 (capacity 3, owner 23) assign 2 users
INSERT INTO AssignedTo (listid, uid) VALUES
  (50, 42),
  (50, 61);

-- Listing 52 (capacity 1, owner 42) no assignment

-- Listing 54 (capacity 1, owner 77) no assignment

-- Listing 55 (capacity 1, owner 30) no assignment

-- Listing 58 (capacity 1, owner 94)
INSERT INTO AssignedTo (listid, uid) VALUES (58, 23);

-- Listing 59 (capacity 1, owner 57)
INSERT INTO AssignedTo (listid, uid) VALUES (59, 42);

-- Listing 62 (capacity 3, owner 84) assign 2 users
INSERT INTO AssignedTo (listid, uid) VALUES
  (62, 57),
  (62, 23);

-- Listing 63 (capacity 1, owner 23)
INSERT INTO AssignedTo (listid, uid) VALUES (63, 42);

-- Listing 66 (capacity 1, owner 61) no assignment

-- Listing 67 (capacity 1, owner 5)
INSERT INTO AssignedTo (listid, uid) VALUES (67, 12);

-- Listing 69 (capacity 1, owner 77) no assignment

-- Listing 70 (capacity 1, owner 6) no assignment

-- Listing 73 (capacity 1, owner 23)
INSERT INTO AssignedTo (listid, uid) VALUES (73, 18);

-- Listing 74 (capacity 1, owner 89)
INSERT INTO AssignedTo (listid, uid) VALUES (74, 61);

-- Listing 77 (capacity 3, owner 77) assign 2 users
INSERT INTO AssignedTo (listid, uid) VALUES
  (77, 6),
  (77, 12);

-- Listing 78 (capacity 1, owner 30)
INSERT INTO AssignedTo (listid, uid) VALUES (78, 42);



-- temporary manaul updated needed for adding reviews (will fix triggers for this later)
-- Step 1: Update listings to 'open'
UPDATE Listings SET status = 'open' WHERE listid IN (7,14,27,31,39,45,53,57,65,68,72);

-- Step 2: Insert AssignedTo (assigned users other than owners)

INSERT INTO AssignedTo (listid, uid) VALUES (7, 12);
INSERT INTO AssignedTo (listid, uid) VALUES (14, 42);
INSERT INTO AssignedTo (listid, uid) VALUES (27, 57);
INSERT INTO AssignedTo (listid, uid) VALUES (31, 12);
INSERT INTO AssignedTo (listid, uid) VALUES (39, 5);
INSERT INTO AssignedTo (listid, uid) VALUES (45, 12);
INSERT INTO AssignedTo (listid, uid) VALUES (53, 42);
INSERT INTO AssignedTo (listid, uid) VALUES (57, 61);
INSERT INTO AssignedTo (listid, uid) VALUES (65, 12);
INSERT INTO AssignedTo (listid, uid) VALUES (68, 42);
INSERT INTO AssignedTo (listid, uid) VALUES (72, 23);

-- Step 3: Update listings to 'completed'
UPDATE Listings SET status = 'completed' WHERE listid IN (7,14,27,31,39,45,53,57,65,68,72);

-- Step 4: Insert reviews (reviewer = owner, reviewee = assigned user)
INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(7, 12, 5, 4, 'Kids survived the evening without any sock casualties. Pretty sure they even liked the babysitter!', '2026-06-22 20:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(14, 42, 61, 3, 'Laptop updated, but now it insists on singing whenever I open it. 3 stars for personality.', '2026-06-20 09:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(27, 57, 23, 5, 'Followed the grocery list exactly. Not a single cookie was sneaked. Legendary!', '2026-06-25 10:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(31, 12, 77, 2, 'Printer works, but my computer now thinks it’s smarter than me. Send help.', '2026-06-23 15:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(39, 5, 84, 5, 'Parcel delivered faster than my coffee cools. Couldn’t ask for better!', '2026-06-22 14:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(45, 12, 35, 4, 'Dog was happy, which is the real win. Couldn’t stop stealing my socks, though.', '2026-06-25 16:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(53, 42, 5, 3, 'Got all the fruits and veggies, but somehow ended up with a suspicious amount of bananas.', '2026-06-24 11:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(57, 61, 42, 1, 'Printer is set up but WiFi now behaves like it’s the boss. One star for chaos, five for effort.', '2026-06-24 10:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(65, 12, 48, 4, 'Package delivered on time, though the humming was a bit much. Very enthusiastic.', '2026-06-22 12:00:00');

INSERT INTO Reviews (listid, reviewer_uid, reviewee_uid, rating, comment, timestamp) VALUES
(72, 23, 57, 2, 'Setup went okay, but now my printer seems to have a mind of its own. A bit spooky.', '2026-06-25 17:00:00');

