USE loket_mbc;

CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin', 'superadmin', 'user') NOT NULL,
    createdAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE user_activities (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    activity VARCHAR(255) NOT NULL,
    createdAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    start_date TIMESTAMP NOT NULL,
    end_date TIMESTAMP NOT NULL,
    location VARCHAR(255) NOT NULL,
    createdAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE ticket_types (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    price INT NOT NULL,
    stock INT NOT NULL,
    max_buy INT NOT NULL,
    platform_fee INT NOT NULL,
    event_id INT NOT NULL,
    createdAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
);

CREATE TABLE transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ticket_amount INT NOT NULL,
    base_price INT NOT NULL,
    total_price INT NOT NULL,
    redeemed_amount INT NOT NULL,
    buy_date TIMESTAMP NOT NULL,
    pay_date TIMESTAMP,
    payment_method VARCHAR(255) NOT NULL,
    payment_status VARCHAR(255) NOT NULL,
    ticket_id VARCHAR(255),
    ticket_status VARCHAR(255),
    ticket_barcode VARCHAR(255),
    external_id VARCHAR(255) NOT NULL,
    ticket_type_id INT NOT NULL,
    user_id INT NOT NULL,
    createdAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (ticket_type_id) REFERENCES ticket_types(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE redeem_histories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id INT NOT NULL,
    user_id INT NOT NULL,
    amount INT NOT NULL,
    latitude VARCHAR(255) NOT NULL,
    longitude VARCHAR(255) NOT NULL,
    createdAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedAt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE sessions (
    sid VARCHAR(255) PRIMARY KEY,
    sess VARCHAR(255) NOT NULL,
    expire TIMESTAMP(6) NOT NULL
);

-- Indexes for the users table
CREATE INDEX idx_users_email ON users(email);


-- Indexes for the user_activities table
CREATE INDEX idx_user_activities_user_id ON user_activities(user_id);

-- Indexes for the ticket_types table
CREATE INDEX idx_ticket_type_event_id ON ticket_types(event_id);

-- Indexes for the transactions table
CREATE INDEX idx_transaction_user_id ON transactions(user_id);

CREATE INDEX idx_transaction_ticket_id ON transactions(ticket_id);

CREATE INDEX idx_transaction_external_id ON transactions(external_id);

-- Indexes for the redeem_histories table
CREATE INDEX idx_redeem_history_transaction_id ON redeem_histories(transaction_id);

CREATE INDEX idx_redeem_history_user_id ON redeem_histories(user_id);

-- Indexes for the sessions table
CREATE INDEX idx_sessions_expire ON sessions(EXPIRE);

