CREATE DATABASE TAREA12

USE TAREA12
GO

CREATE TABLE Country (
    country_id INT NOT NULL PRIMARY KEY,
    country_name VARCHAR(200)
);

CREATE TABLE Address (
    address_id INT NOT NULL PRIMARY KEY,
    street_number VARCHAR(10),
    street_name VARCHAR(200),
    city VARCHAR(100),
    country_id INT,
    FOREIGN KEY (country_id) REFERENCES Country(country_id)
);

CREATE TABLE Address_Status (
    status_id INT NOT NULL PRIMARY KEY,
    address_status VARCHAR(30)
);

CREATE TABLE Customer (
    customer_id INT NOT NULL PRIMARY KEY,
    first_name VARCHAR(200),
    last_name VARCHAR(200),
    email VARCHAR(350)
);

CREATE TABLE Customer_Address (
    customer_id INT NOT NULL,
    address_id INT NOT NULL,
    status_id INT,
    PRIMARY KEY (customer_id, address_id),
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id),
    FOREIGN KEY (address_id) REFERENCES Address(address_id),
    FOREIGN KEY (status_id) REFERENCES Address_Status(status_id)
);

CREATE TABLE Shipping_Method (
    method_id INT NOT NULL PRIMARY KEY,
    method_name VARCHAR(100),
    cost DECIMAL(6,2)
);

CREATE TABLE Order_Status (
    status_id INT NOT NULL PRIMARY KEY,
    status_value VARCHAR(20)
);

CREATE TABLE Customer_Order (
    order_id INT NOT NULL PRIMARY KEY,
    order_date DATETIME,
    customer_id INT,
    shipping_method_id INT,
    dest_address_id INT,
    FOREIGN KEY (customer_id) REFERENCES Customer(customer_id),
    FOREIGN KEY (shipping_method_id) REFERENCES Shipping_Method(method_id),
    FOREIGN KEY (dest_address_id) REFERENCES Address(address_id)
);

CREATE TABLE Order_History (
    history_id INT NOT NULL PRIMARY KEY,
    order_id INT,
    status_id INT,
    status_date DATETIME,
    FOREIGN KEY (order_id) REFERENCES Customer_Order(order_id),
    FOREIGN KEY (status_id) REFERENCES Order_Status(status_id)
);

CREATE TABLE Author (
    author_id INT NOT NULL PRIMARY KEY,
    author_name VARCHAR(400)
);

CREATE TABLE Book_Language (
    language_id INT NOT NULL PRIMARY KEY,
    language_code VARCHAR(8),
    language_name VARCHAR(50)
);

CREATE TABLE Publisher (
    publisher_id INT NOT NULL PRIMARY KEY,
    publisher_name VARCHAR(400)
);

CREATE TABLE Book (
    book_id INT NOT NULL PRIMARY KEY,
    title VARCHAR(400),
    isbn13 VARCHAR(13),
    language_id INT,
    num_pages INT,
    publication_date DATE,
    publisher_id INT,
    FOREIGN KEY (language_id) REFERENCES Book_Language(language_id),
    FOREIGN KEY (publisher_id) REFERENCES Publisher(publisher_id)
);

CREATE TABLE Book_Author (
    book_id INT NOT NULL,
    author_id INT NOT NULL,
    PRIMARY KEY (book_id, author_id),
    FOREIGN KEY (book_id) REFERENCES Book(book_id),
    FOREIGN KEY (author_id) REFERENCES Author(author_id)
);

CREATE TABLE Order_Line (
    line_id INT NOT NULL PRIMARY KEY,
    order_id INT,
    book_id INT,
    price DECIMAL(5,2),
    FOREIGN KEY (order_id) REFERENCES Customer_Order(order_id),
    FOREIGN KEY (book_id) REFERENCES Book(book_id)
);
GO

--Ejercicio 1

CREATE FUNCTION dbo.CalcularEdadPromedioLibros(@author_id INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
	DECLARE @PromedioEdad DECIMAL(10,2);
	SELECT @PromedioEdad = AVG(DATEDIFF(YEAR, publication_date ,GETDATE()))
	FROM Book b
	INNER JOIN Book_Author ba ON b.book_id = ba.book_id
    WHERE ba.author_id = @author_id 
		AND b.publication_date <= GETDATE() 
		AND b.publication_date IS NOT NULL;
    RETURN @PromedioEdad;
END;
GO

--Ejercicio 2

CREATE FUNCTION dbo.CalcularPrecioPromedioLibro(@book_id INT)
RETURNS TABLE
AS
RETURN
(
    WITH Ventas AS (
        SELECT 
            book_id,
            COUNT(*) AS ventas,
            AVG(price) AS precio_promedio
        FROM Order_Line
        GROUP BY book_id
    ),
    Mediana AS (
        SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ventas) 
            OVER () AS mediana
        FROM Ventas
    )
    SELECT
        v.book_id,
        v.precio_promedio,
        v.ventas,
        m.mediana,
        CASE 
            WHEN v.ventas < m.mediana THEN 
                v.precio_promedio * (1 + (m.mediana - v.ventas) / m.mediana)
            ELSE 
                v.precio_promedio
        END AS precio_ajustado
    FROM Ventas v
    CROSS JOIN Mediana m
    WHERE v.book_id = @book_id
);
GO

--Ejercicio 3

CREATE FUNCTION dbo.ListarCostoReabastecimiento(@author_id INT)
RETURNS TABLE
AS
RETURN
(
    SELECT
        b.book_id,
        MIN(ol.price) AS precio_estimado,
        GREATEST(
            (
                SELECT COUNT(*)
                FROM Order_Line ols
                JOIN Customer_Order co ON ols.order_id = co.order_id
                JOIN Order_History oh ON oh.order_id = co.order_id
                WHERE ols.book_id = b.book_id
                  AND oh.history_id = (
                        SELECT MAX(history_id)
                        FROM Order_History
                        WHERE order_id = co.order_id
                  )
                  AND oh.status_id IN (1,2)
            ) - 1, 0
        ) AS faltantes,
        GREATEST(
            (
                SELECT COUNT(*)
                FROM Order_Line ols
                JOIN Customer_Order co ON ols.order_id = co.order_id
                JOIN Order_History oh ON oh.order_id = co.order_id
                WHERE ols.book_id = b.book_id
                  AND oh.history_id = (
                        SELECT MAX(history_id)
                        FROM Order_History
                        WHERE order_id = co.order_id
                  )
                  AND oh.status_id IN (1,2)
            ) - 1, 0
        ) * MIN(ol.price) AS costo_total
    FROM Book_Author ba
    JOIN Book b ON ba.book_id = b.book_id
    LEFT JOIN Order_Line ol ON b.book_id = ol.book_id
    WHERE ba.author_id = @author_id
    GROUP BY b.book_id
);
GO

--Ejercicio 4

CREATE FUNCTION dbo.ListarLibrosPorIdiomas(@author_id INT)
RETURNS TABLE
AS
RETURN
(
    SELECT 
        bl.language_id,
        bl.language_name,
        COUNT(ol.line_id) AS libros_vendidos,
        SUM(ol.price) AS total_ingresos
    FROM Book_Author ba
        INNER JOIN Book b ON ba.book_id = b.book_id
        INNER JOIN Book_Language bl ON b.language_id = bl.language_id
        INNER JOIN Order_Line ol ON b.book_id = ol.book_id
    WHERE ba.author_id = @author_id
    GROUP BY bl.language_id, bl.language_name
);
GO

--Ejercicio 5

CREATE FUNCTION dbo.ListarLibrosPorEditorial(@Año INT)
RETURNS TABLE
AS
RETURN
(
     SELECT 
        p.publisher_name,
        a.city,
        MONTH(co.order_date) AS mes,
        SUM(ol.price) AS total_mes,
        CASE 
            WHEN SIGN(
                SUM(ol.price) - LAG(SUM(ol.price)) 
                OVER ( PARTITION BY p.publisher_name, a.city 
                    ORDER BY MONTH(co.order_date)
                    )
            ) = 1 THEN 'Aumenta'
            WHEN SIGN(
                SUM(ol.price) - LAG(SUM(ol.price)) 
                OVER (PARTITION BY p.publisher_name, a.city 
                    ORDER BY MONTH(co.order_date)
                )
            ) = -1 THEN 'Disminuye'
            ELSE 'Igual'
        END AS tendencia
    FROM Order_Line ol
    JOIN Book b ON ol.book_id = b.book_id
    JOIN Publisher p ON b.publisher_id = p.publisher_id
    JOIN Customer_Order co ON ol.order_id = co.order_id
    JOIN Address a ON co.dest_address_id = a.address_id
    WHERE YEAR(co.order_date) = @Año
    GROUP BY p.publisher_name, a.city, MONTH(co.order_date)
);
GO

--Ejercicio 6

CREATE FUNCTION dbo.ListarResumenDeDemanda(
    @FechaInicio DATE,
    @FechaFin DATE,
    @MetodoEnvio INT = NULL
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        sm.method_id,
        sm.method_name,
        ol.book_id,
        COUNT(*) AS ventas,
        AVG(COUNT(*)) OVER (PARTITION BY sm.method_id) AS demanda_promedio
    FROM Order_Line ol
    INNER JOIN Customer_Order co ON ol.order_id = co.order_id
    INNER JOIN Shipping_Method sm ON co.shipping_method_id = sm.method_id
    WHERE co.order_date BETWEEN @FechaInicio AND @FechaFin
      AND ( @MetodoEnvio IS NULL OR sm.method_id = @MetodoEnvio )
    GROUP BY sm.method_id, sm.method_name, ol.book_id
);