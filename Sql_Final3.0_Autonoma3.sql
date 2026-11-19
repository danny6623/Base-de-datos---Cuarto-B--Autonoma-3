
/* ============================================================
   BLOQUE 1. CREACION DE LA BASE DE DATOS Y TABLAS
   ============================================================ */
DROP DATABASE IF EXISTS RecuperacionLogistica;
CREATE DATABASE RecuperacionLogistica;
USE RecuperacionLogistica;

CREATE TABLE Sucursales (
    id_sucursal      INT AUTO_INCREMENT PRIMARY KEY,
    nombre_ciudad    VARCHAR(80) NOT NULL,
    capacidad_maxima INT NOT NULL,
    CONSTRAINT chk_capacidad CHECK (capacidad_maxima > 0)
) ENGINE=InnoDB;

CREATE TABLE Paquetes (
    id_paquete   INT AUTO_INCREMENT PRIMARY KEY,
    descripcion  VARCHAR(150)  NOT NULL,
    peso         DECIMAL(8,2)  NOT NULL,
    costo_envio  DECIMAL(10,2) NOT NULL,
    id_sucursal  INT           NOT NULL,
    fecha_envio  DATE          NOT NULL DEFAULT (CURRENT_DATE),
    CONSTRAINT chk_peso  CHECK (peso > 0),
    CONSTRAINT chk_costo CHECK (costo_envio > 0),
    CONSTRAINT fk_paquete_sucursal FOREIGN KEY (id_sucursal)
        REFERENCES Sucursales (id_sucursal)
) ENGINE=InnoDB;

-- >>>  Estructura de las tablas.
SHOW TABLES;
SHOW CREATE TABLE Sucursales;
SHOW CREATE TABLE Paquetes;


/* ============================================================
   BLOQUE 2. TRIGGER DE CAPACIDAD (regla de negocio)
   Impide superar la capacidad maxima de una sucursal.
   ============================================================ */
DELIMITER $$
CREATE TRIGGER trg_validar_capacidad
BEFORE INSERT ON Paquetes
FOR EACH ROW
BEGIN
    DECLARE v_actual INT;
    DECLARE v_max INT;
    SELECT capacidad_maxima INTO v_max
      FROM Sucursales WHERE id_sucursal = NEW.id_sucursal;
    SELECT COUNT(*) INTO v_actual
      FROM Paquetes WHERE id_sucursal = NEW.id_sucursal;
    IF v_actual >= v_max THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Sucursal sin capacidad disponible';
    END IF;
END$$
DELIMITER ;

-- >>> Trigger creado correctamente.
SHOW TRIGGERS;


/* ============================================================
   BLOQUE 3. DATOS VALIDOS
   ============================================================ */
INSERT INTO Sucursales (nombre_ciudad, capacidad_maxima) VALUES
 ('Quito', 100), ('Guayaquil', 100), ('Riobamba', 2);

INSERT INTO Paquetes (descripcion, peso, costo_envio, id_sucursal, fecha_envio) VALUES
 ('Laptop',   2.50, 15.00, 1, '2026-11-02'),
 ('Celular',  0.50,  8.00, 2, '2026-11-05'),
 ('Libros',   3.00,  6.50, 1, '2026-11-10'),
 ('Teclado',  1.20,  5.00, 3, '2026-11-12'),
 ('Monitor',  4.80, 12.00, 3, '2026-11-15');

-- >>> Datos validos aceptados.

SELECT * FROM Sucursales;
SELECT * FROM Paquetes;


/* ============================================================
   BLOQUE 4. DATOS INVALIDOS
   ============================================================ */

-- >>> Error por peso negativo (CHECK chk_peso, error 3819)
INSERT INTO Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES ('Paquete invalido', -1.00, 10.00, 1);

-- >>> Error por costo igual a cero (CHECK chk_costo, error 3819)
INSERT INTO Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES ('Paquete invalido', 2.00, 0, 1);

-- >>> Error por sucursal inexistente (FOREIGN KEY, error 1452)
INSERT INTO Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES ('Paquete invalido', 2.00, 10.00, 99);

-- >>> Error del TRIGGER: Riobamba (capacidad 2) ya esta llena
--     (error 1644, mensaje "Sucursal sin capacidad disponible")
INSERT INTO Paquetes (descripcion, peso, costo_envio, id_sucursal)
VALUES ('Paquete extra', 1.00, 4.00, 3);


/* ============================================================
   BLOQUE 5. CONTROL DE CONCURRENCIA
   ============================================================ */

/* ---------- CASO 1: LECTURA SUCIA (READ UNCOMMITTED) ---------- */

-- [1-A] SESION A
START TRANSACTION;
UPDATE Paquetes SET costo_envio = 999.00 WHERE id_paquete = 1;   -- NO hacer commit

-- [1-B] SESION B
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
START TRANSACTION;
-- >>> Sesion B lee 999.00 (dato nunca confirmado = lectura sucia)
SELECT id_paquete, costo_envio FROM Paquetes WHERE id_paquete = 1;

-- [1-C] SESION A
ROLLBACK;

-- [1-D] SESION B
-- >>> Ahora B ve 15.00: habia leido un dato que ya no existe
SELECT id_paquete, costo_envio FROM Paquetes WHERE id_paquete = 1;
COMMIT;

/* ---- Misma prueba con READ COMMITTED: la lectura sucia desaparece ---- */
-- [1-E] SESION A
START TRANSACTION;
UPDATE Paquetes SET costo_envio = 999.00 WHERE id_paquete = 1;   -- NO hacer commit

-- [1-F] SESION B
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
-- >>> Con READ COMMITTED, B sigue viendo 15.00 (no ve el 999 sin confirmar)
SELECT id_paquete, costo_envio FROM Paquetes WHERE id_paquete = 1;
COMMIT;

-- [1-G] SESION A
ROLLBACK;


/* ---------- CASO 2: LECTURA NO REPETIBLE

/* 2.a  READ COMMITTED -> el reporte cambia dentro de la misma transaccion */
-- [2a-1] SESION B
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT SUM(costo_envio) AS total_reporte FROM Paquetes;     -- 1a lectura (46.50)

-- [2a-2] SESION A  (autocommit: el cambio queda confirmado)
UPDATE Paquetes SET costo_envio = 20.00 WHERE id_paquete = 1;

-- [2a-3] SESION B
-- >>> 2a lectura DISTINTA a la 1a (51.50): lectura no repetible.
SELECT SUM(costo_envio) AS total_reporte FROM Paquetes;
COMMIT;

-- SESION A (restaurar el valor original)
UPDATE Paquetes SET costo_envio = 15.00 WHERE id_paquete = 1;

/* 2.b  REPEATABLE READ -> el reporte se mantiene estable */
-- [2b-1] SESION B
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT SUM(costo_envio) AS total_reporte FROM Paquetes;     -- 1a lectura (46.50)

-- [2b-2] SESION A
UPDATE Paquetes SET costo_envio = 20.00 WHERE id_paquete = 1;

-- [2b-3] SESION B
-- >>> 2a lectura IGUAL a la 1a (46.50), aunque A ya confirmo
SELECT SUM(costo_envio) AS total_reporte FROM Paquetes;
COMMIT;
SELECT SUM(costo_envio) AS total_despues_del_commit FROM Paquetes;  -- ahora si cambia

-- SESION A (restaurar)
UPDATE Paquetes SET costo_envio = 15.00 WHERE id_paquete = 1;

/* 2.c  SERIALIZABLE -> la escritura de A queda BLOQUEADA hasta que B termine */
-- [2c-1] SESION B
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
START TRANSACTION;
SELECT SUM(costo_envio) AS total_reporte FROM Paquetes;     -- B bloquea lo que lee

-- [2c-2] SESION A  (acortar la espera para no aguardar 50 s)
SET SESSION innodb_lock_wait_timeout = 10;
-- >>> La sentencia queda "ejecutando" ~10 s y luego muestra
--     Error 1205: Lock wait timeout exceeded  (A fue bloqueada por B)
UPDATE Paquetes SET costo_envio = 20.00 WHERE id_paquete = 1;

-- [2c-3] SESION B
COMMIT;      -- al terminar B, A ya puede escribir

/* Dejar todo en estado normal al terminar el bloque 5: */
UPDATE Paquetes SET costo_envio = 15.00 WHERE id_paquete = 1;
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;   -- valor por defecto de MySQL


/* ============================================================
   BLOQUE 6. RESPALDOS 
   ============================================================ */
-- >>> Log binario activo.

SHOW VARIABLES LIKE 'log_bin';
SHOW BINARY LOGS;

/* ============================================================
   BLOQUE 7. VERIFICACION DE LA RESTAURACION
   ============================================================ */
-- >>>  Conteos iguales entre produccion y prueba (5 y 5)
SELECT 'Produccion' AS entorno, COUNT(*) AS total FROM RecuperacionLogistica.Paquetes
UNION ALL
SELECT 'Prueba',               COUNT(*)           FROM RecuperacionLogistica_Test.Paquetes;


/* ============================================================
   BLOQUE 9. REPORTE PARAMETRICO
   ============================================================ */
USE RecuperacionLogistica;
DELIMITER $$
CREATE PROCEDURE sp_reporte_paquetes(
    IN p_inicio DATE, IN p_fin DATE, IN p_sucursal INT)
BEGIN
    SELECT p.id_paquete, p.descripcion, p.peso, p.costo_envio,
           s.nombre_ciudad, p.fecha_envio
      FROM Paquetes p
      JOIN Sucursales s ON s.id_sucursal = p.id_sucursal
     WHERE p.fecha_envio BETWEEN p_inicio AND p_fin
       AND (p_sucursal IS NULL OR p.id_sucursal = p_sucursal);
END$$
DELIMITER ;

-- >>> Reporte por rango de fechas y sucursal (Quito: 2 paquetes)
CALL sp_reporte_paquetes('2026-11-01', '2026-11-30', 1);