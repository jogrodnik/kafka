--
-- DB PostgreSQL bootstrap
--

SET default_transaction_read_only = off;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE db;
ALTER ROLE db WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
CREATE ROLE db_admin;
ALTER ROLE db_admin WITH NOSUPERUSER INHERIT NOCREATEROLE CREATEDB LOGIN NOREPLICATION NOBYPASSRLS PASSWORD '';

--
-- Role memberships
--

GRANT db TO db_admin GRANTED BY db_admin;

--
-- Name: db; Type: DATABASE; Schema: -; Owner: db_admin
--

CREATE DATABASE db ENCODING = 'UTF8' LC_COLLATE = 'nb_NO.utf8' LC_CTYPE = 'nb_NO.utf8';
ALTER DATABASE db OWNER TO db_admin;
