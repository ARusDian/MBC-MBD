USE loket_mbc;

INSERT INTO users (
            name,
            email,
            password,
            role
        )
        VALUES (
            'Keren',
            'keren@gmail.com',
            '$2a$12$iCPQ.4j.rlj49tZoGrkp9uF3Lgs4CptR/6px5CceuW1LM8JnRGQnG',
            'admin'
        );
        
        
CALL sp_user_detail_by_email("keren@gmail.com");


DELIMITER //

CREATE PROCEDURE sp_min_one(IN input_value INT, OUT output_value INT)
BEGIN
    SELECT input_valute - 1
END //

DELIMITER ;

CALL sp_min_one(10, @hasil);
SELECT @hasil;



DELIMITER //
CREATE PROCEDURE sp_min_one_no_ret(IN input_value INT)
BEGIN
    SELECT input_value - 1;
END //

DELIMITER ;

CALL sp_min_one_no_ret(10);