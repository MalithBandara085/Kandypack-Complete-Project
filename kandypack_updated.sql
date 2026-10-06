--
-- PostgreSQL database dump
--

\restrict 9SR7bGBK8DIud4XFSPXAJBU1CVfB8yiMwPbgnrJMjezs4Q60yaQDhjyY24gaohN

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: assign_order_to_trips(character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.assign_order_to_trips(IN p_order_id character varying, IN p_route_id character varying, IN p_preferred_trip_id character varying DEFAULT NULL::character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_order public.customer_order%ROWTYPE;
    v_route public.route%ROWTYPE;
    v_city varchar(10);
    v_customer_city varchar(10);
    v_earliest timestamp := clock_timestamp() AT TIME ZONE 'Asia/Colombo';
    v_preferred public.train_schedule%ROWTYPE;
    v_trip record;
    v_item record;
    v_available numeric;
    v_take integer;
BEGIN
    SELECT * INTO v_order FROM public.customer_order WHERE order_id = p_order_id FOR UPDATE;
    IF NOT FOUND OR v_order.status <> 'placed' THEN
        RAISE EXCEPTION 'Order not found or is not available for scheduling.' USING ERRCODE = '23514';
    END IF;
    IF EXISTS (SELECT 1 FROM public.order_travel WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Order already has allocations; rescheduling is not supported by this operation.' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.order_item WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Order must have at least one item.' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO v_route FROM public.route WHERE route_id = p_route_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Route not found.' USING ERRCODE = '23514';
    END IF;
    -- Serialize allocations for this destination; lock trips in a stable chronological order.
    SELECT city_id INTO v_city FROM public.store WHERE store_id = v_route.store_id FOR UPDATE;
    SELECT city_id INTO v_customer_city FROM public.customer WHERE customer_id = v_order.customer_id;
    IF v_customer_city <> v_city THEN
        RAISE EXCEPTION 'Select a route in the customer delivery city.' USING ERRCODE = '23514';
    END IF;

    IF NULLIF(trim(p_preferred_trip_id), '') IS NOT NULL THEN
        SELECT * INTO v_preferred FROM public.train_schedule WHERE trip_id = p_preferred_trip_id;
        IF NOT FOUND OR v_preferred.store_id <> v_route.store_id OR v_preferred.city_id <> v_city
           OR v_preferred.departure_datetime <= v_earliest THEN
            RAISE EXCEPTION 'Preferred trip is missing, has already departed, or serves a different destination.' USING ERRCODE = '23514';
        END IF;
        v_earliest := v_preferred.departure_datetime;
    END IF;

    FOR v_trip IN
        SELECT ts.* FROM public.train_schedule ts
        WHERE ts.store_id = v_route.store_id AND ts.city_id = v_city
          AND ts.departure_datetime >= v_earliest
          AND ts.departure_datetime > (clock_timestamp() AT TIME ZONE 'Asia/Colombo')
          AND ts.arrival_datetime + v_route.max_delivery_time * interval '1 hour'
              < (v_order.delivery_date + 1)::timestamp
        ORDER BY ts.departure_datetime, ts.trip_id FOR UPDATE OF ts
    LOOP
        FOR v_item IN
            SELECT oi.product_id, p.space_consumption,
                   oi.quantity - COALESCE((SELECT sum(a.quantity) FROM public.order_trip_item a
                     WHERE a.order_id = oi.order_id AND a.product_id = oi.product_id),0) AS remaining
            FROM public.order_item oi JOIN public.product p USING (product_id)
            WHERE oi.order_id = p_order_id
            ORDER BY p.space_consumption DESC, oi.product_id
        LOOP
            SELECT available_capacity INTO v_available FROM public.train_schedule WHERE trip_id = v_trip.trip_id;
            v_take := LEAST(v_item.remaining, floor(v_available / v_item.space_consumption))::integer;
            IF v_take > 0 THEN
                INSERT INTO public.order_travel(order_id, trip_id, route_id)
                VALUES (p_order_id, v_trip.trip_id, p_route_id) ON CONFLICT DO NOTHING;
                INSERT INTO public.order_trip_item(order_id, trip_id, product_id, quantity, space_per_unit)
                VALUES (p_order_id, v_trip.trip_id, v_item.product_id, v_take, v_item.space_consumption);
            END IF;
        END LOOP;
        EXIT WHEN NOT EXISTS (
            SELECT 1 FROM public.order_item oi WHERE oi.order_id = p_order_id AND oi.quantity <>
            COALESCE((SELECT sum(a.quantity) FROM public.order_trip_item a
                      WHERE a.order_id = oi.order_id AND a.product_id = oi.product_id),0)
        );
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM public.order_item oi WHERE oi.order_id = p_order_id AND oi.quantity <>
        COALESCE((SELECT sum(a.quantity) FROM public.order_trip_item a
                  WHERE a.order_id = oi.order_id AND a.product_id = oi.product_id),0)
    ) THEN
        RAISE EXCEPTION 'Not enough suitable train capacity before the delivery date. Choose a later date or add future trips.' USING ERRCODE = '23514';
    END IF;
    UPDATE public.customer_order SET status = 'scheduled' WHERE order_id = p_order_id;
END $$;


--
-- Name: assignordertotrip(character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.assignordertotrip(IN p_order_id character varying, IN p_preferred_trip_id character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE EXCEPTION 'Use CALL assign_order_to_trips(order_id, route_id, preferred_trip_id); the route is required.';
END $$;


--
-- Name: calculateorderspace(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculateorderspace(p_order_id character varying) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_space DECIMAL(10,2);
BEGIN
    SELECT COALESCE(SUM(oi.quantity * p.space_consumption), 0)
    INTO v_total_space
    FROM ORDER_ITEM oi
    JOIN PRODUCT p ON oi.product_id = p.product_id
    WHERE oi.order_id = p_order_id;

    RETURN v_total_space;
END;
$$;


--
-- Name: calculateordertotal(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.calculateordertotal(p_order_id character varying) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total DECIMAL(10,2);
BEGIN
    SELECT COALESCE(SUM(quantity * price), 0)
    INTO v_total
    FROM ORDER_ITEM
    WHERE order_id = p_order_id;

    RETURN v_total;
END;
$$;


--
-- Name: getdriverweeklyhours(character varying, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.getdriverweeklyhours(p_driver_id character varying, p_reference_date date) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_hours DECIMAL(6,2);
BEGIN
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600), 0)
    INTO v_total_hours
    FROM TRUCK_DISPATCH
    WHERE driver_id = p_driver_id
    AND date_trunc('week', start_time) = date_trunc('week', p_reference_date::timestamp);

    RETURN v_total_hours;
END;
$$;


--
-- Name: kp_booked_item_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kp_booked_item_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_order_id varchar(10);
BEGIN
    IF TG_OP = 'INSERT' THEN v_order_id := NEW.order_id; ELSE v_order_id := OLD.order_id; END IF;
    PERFORM 1 FROM public.customer_order WHERE order_id = v_order_id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM public.order_trip_item WHERE order_id = v_order_id) THEN
        RAISE EXCEPTION 'Booked order items cannot be edited; create a new order instead.' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.order_id <> OLD.order_id THEN
        RAISE EXCEPTION 'Moving items between orders is not supported.' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;


--
-- Name: kp_booked_travel_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kp_booked_travel_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.order_trip_item
               WHERE order_id = OLD.order_id AND trip_id = OLD.trip_id) THEN
        RAISE EXCEPTION 'Booked travel records cannot be edited; create a new order instead.' USING ERRCODE = '23514';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;


--
-- Name: kp_cancel_reservations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kp_cancel_reservations() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
        UPDATE public.order_trip_item SET reservation_active = false
        WHERE order_id = NEW.order_id AND reservation_active;
    END IF;
    RETURN NEW;
END $$;


--
-- Name: kp_new_trip_capacity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kp_new_trip_capacity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.allocated_capacity IS NULL THEN
        NEW.allocated_capacity := NEW.available_capacity;
    END IF;
    RETURN NEW;
END $$;


--
-- Name: kp_order_status_guard(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kp_order_status_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
    IF NOT ((OLD.status = 'placed' AND NEW.status IN ('scheduled','cancelled'))
        OR (OLD.status = 'scheduled' AND NEW.status IN ('dispatched','cancelled'))
        OR (OLD.status = 'dispatched' AND NEW.status = 'delivered')) THEN
        RAISE EXCEPTION 'Invalid order status transition: % -> %.', OLD.status, NEW.status USING ERRCODE = '23514';
    END IF;
    IF NEW.status = 'scheduled' THEN
        IF NOT EXISTS (SELECT 1 FROM public.order_item WHERE order_id = NEW.order_id)
           OR EXISTS (SELECT 1 FROM public.order_item oi WHERE oi.order_id = NEW.order_id AND oi.quantity <>
             COALESCE((SELECT sum(a.quantity) FROM public.order_trip_item a
                       WHERE a.order_id = oi.order_id AND a.product_id = oi.product_id AND a.reservation_active),0)) THEN
            RAISE EXCEPTION 'An order must be fully allocated before it is scheduled.' USING ERRCODE = '23514';
        END IF;
    END IF;
    IF NEW.status = 'cancelled' THEN
        -- Same destination/trip lock order as the allocator, before checking departure times.
        PERFORM s.store_id FROM public.store s
        WHERE s.store_id IN (SELECT ts.store_id FROM public.order_trip_item a
            JOIN public.train_schedule ts USING (trip_id) WHERE a.order_id = NEW.order_id AND a.reservation_active)
        ORDER BY s.store_id FOR UPDATE;
        PERFORM ts.trip_id FROM public.train_schedule ts
        WHERE ts.trip_id IN (SELECT trip_id FROM public.order_trip_item WHERE order_id = NEW.order_id AND reservation_active)
        ORDER BY ts.departure_datetime, ts.trip_id FOR UPDATE;
        IF EXISTS (SELECT 1 FROM public.order_trip_item a JOIN public.train_schedule ts USING (trip_id)
                   WHERE a.order_id = NEW.order_id AND a.reservation_active
                   AND ts.departure_datetime <= (clock_timestamp() AT TIME ZONE 'Asia/Colombo')) THEN
            RAISE EXCEPTION 'Cannot release an order after a reserved train has departed.' USING ERRCODE = '23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;


--
-- Name: kp_reserve_train_space(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kp_reserve_train_space() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_status varchar(20);
    v_order_qty integer;
    v_assigned_qty bigint;
    v_space numeric;
    v_delivery date;
    v_customer_city varchar(10);
    v_route_store varchar(10);
    v_route_city varchar(10);
    v_max_hours numeric;
    v_trip public.train_schedule%ROWTYPE;
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Keep allocation history. Cancel an eligible order to release its reservation.' USING ERRCODE = '23514';
    END IF;

    SELECT co.status, co.delivery_date, c.city_id
    INTO v_status, v_delivery, v_customer_city
    FROM public.customer_order co JOIN public.customer c USING (customer_id)
    WHERE co.order_id = NEW.order_id FOR UPDATE OF co;

    IF TG_OP = 'UPDATE' THEN
        IF ROW(NEW.order_id, NEW.trip_id, NEW.product_id, NEW.quantity, NEW.space_per_unit)
           IS DISTINCT FROM ROW(OLD.order_id, OLD.trip_id, OLD.product_id, OLD.quantity, OLD.space_per_unit)
           OR OLD.reservation_active = false OR NEW.reservation_active = true
           OR v_status <> 'cancelled' THEN
            RAISE EXCEPTION 'Allocation rows are immutable; only cancellation can release reservations.' USING ERRCODE = '23514';
        END IF;
        UPDATE public.train_schedule
        SET available_capacity = available_capacity + OLD.quantity * OLD.space_per_unit
        WHERE trip_id = OLD.trip_id;
        RETURN NEW;
    END IF;

    IF v_status IS DISTINCT FROM 'placed' OR NOT NEW.reservation_active THEN
        RAISE EXCEPTION 'Only a placed order can receive new train allocations.' USING ERRCODE = '23514';
    END IF;

    SELECT oi.quantity, p.space_consumption INTO v_order_qty, NEW.space_per_unit
    FROM public.order_item oi JOIN public.product p USING (product_id)
    WHERE oi.order_id = NEW.order_id AND oi.product_id = NEW.product_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Order item does not exist.' USING ERRCODE = '23514';
    END IF;
    SELECT COALESCE(sum(quantity),0) INTO v_assigned_qty
    FROM public.order_trip_item WHERE order_id = NEW.order_id AND product_id = NEW.product_id;
    IF NEW.quantity + v_assigned_qty > v_order_qty THEN
        RAISE EXCEPTION 'Allocated quantity exceeds the ordered quantity.' USING ERRCODE = '23514';
    END IF;

    SELECT r.store_id, s.city_id, r.max_delivery_time
    INTO v_route_store, v_route_city, v_max_hours
    FROM public.order_travel ot JOIN public.route r USING (route_id)
    JOIN public.store s ON s.store_id = r.store_id
    WHERE ot.order_id = NEW.order_id AND ot.trip_id = NEW.trip_id;
    SELECT * INTO v_trip FROM public.train_schedule WHERE trip_id = NEW.trip_id FOR UPDATE;
    IF v_route_store IS NULL OR v_trip.trip_id IS NULL
       OR v_route_store <> v_trip.store_id OR v_route_city <> v_trip.city_id
       OR v_customer_city <> v_route_city THEN
        RAISE EXCEPTION 'Customer, route, store and trip destination must match.' USING ERRCODE = '23514';
    END IF;
    IF v_trip.departure_datetime <= (clock_timestamp() AT TIME ZONE 'Asia/Colombo')
       OR v_trip.arrival_datetime + v_max_hours * interval '1 hour' >= (v_delivery + 1)::timestamp THEN
        RAISE EXCEPTION 'Trip must be in the future and allow delivery by the requested date.' USING ERRCODE = '23514';
    END IF;
    v_space := NEW.quantity * NEW.space_per_unit;
    UPDATE public.train_schedule SET available_capacity = available_capacity - v_space
    WHERE trip_id = NEW.trip_id AND available_capacity >= v_space;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient capacity for the requested allocation.' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;


--
-- Name: trg_fn_assistant_max_consecutive(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_assistant_max_consecutive() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    consecutive_count INT;
BEGIN
    SELECT COUNT(*) INTO consecutive_count
    FROM TRUCK_DISPATCH
    WHERE assistant_id = NEW.assistant_id
    AND end_time >= NEW.start_time - INTERVAL '12 hours';

    IF consecutive_count >= 2 THEN
        RAISE EXCEPTION 'Assistant cannot exceed 2 consecutive route assignments';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_assistant_no_overlap(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_assistant_no_overlap() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    conflict_count INT;
BEGIN
    SELECT COUNT(*) INTO conflict_count
    FROM TRUCK_DISPATCH
    WHERE assistant_id = NEW.assistant_id
    AND NEW.start_time < end_time
    AND NEW.end_time > start_time;

    IF conflict_count > 0 THEN
        RAISE EXCEPTION 'Assistant already has an overlapping dispatch';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_assistant_weekly_hours(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_assistant_weekly_hours() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    total_hours DECIMAL(6,2);
BEGIN
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600), 0)
    INTO total_hours
    FROM TRUCK_DISPATCH
    WHERE assistant_id = NEW.assistant_id
    AND date_trunc('week', start_time) = date_trunc('week', NEW.start_time);

    IF total_hours + (EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 3600) > 60 THEN
        RAISE EXCEPTION 'Assistant weekly hour limit (60 hrs) exceeded';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_deduct_capacity(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_deduct_capacity() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    needed_space DECIMAL(10,2);
    remaining_space DECIMAL(10,2);
BEGIN
    SELECT SUM(oi.quantity * p.space_consumption)
    INTO needed_space
    FROM ORDER_ITEM oi
    JOIN PRODUCT p ON oi.product_id = p.product_id
    WHERE oi.order_id = NEW.order_id;

    SELECT available_capacity INTO remaining_space
    FROM TRAIN_SCHEDULE
    WHERE trip_id = NEW.trip_id;

    IF needed_space > remaining_space THEN
        RAISE EXCEPTION 'Order exceeds available train capacity for this trip';
    ELSE
        UPDATE TRAIN_SCHEDULE
        SET available_capacity = available_capacity - needed_space
        WHERE trip_id = NEW.trip_id;
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_driver_no_consecutive(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_driver_no_consecutive() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    last_end TIMESTAMP;
BEGIN
    SELECT MAX(end_time) INTO last_end
    FROM TRUCK_DISPATCH
    WHERE driver_id = NEW.driver_id;

    IF last_end IS NOT NULL AND NEW.start_time <= last_end + INTERVAL '1 hour' THEN
        RAISE EXCEPTION 'Driver cannot be assigned two consecutive deliveries without a break';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_driver_no_overlap(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_driver_no_overlap() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    conflict_count INT;
BEGIN
    SELECT COUNT(*) INTO conflict_count
    FROM TRUCK_DISPATCH
    WHERE driver_id = NEW.driver_id
    AND NEW.start_time < end_time
    AND NEW.end_time > start_time;

    IF conflict_count > 0 THEN
        RAISE EXCEPTION 'Driver already has an overlapping dispatch';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_driver_weekly_hours(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_driver_weekly_hours() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    total_hours DECIMAL(6,2);
BEGIN
    SELECT COALESCE(SUM(EXTRACT(EPOCH FROM (end_time - start_time)) / 3600), 0)
    INTO total_hours
    FROM TRUCK_DISPATCH
    WHERE driver_id = NEW.driver_id
    AND date_trunc('week', start_time) = date_trunc('week', NEW.start_time);

    IF total_hours + (EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 3600) > 40 THEN
        RAISE EXCEPTION 'Driver weekly hour limit (40 hrs) exceeded';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_truck_no_overlap(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_truck_no_overlap() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    conflict_count INT;
BEGIN
    SELECT COUNT(*) INTO conflict_count
    FROM TRUCK_DISPATCH
    WHERE truck_id = NEW.truck_id
    AND NEW.start_time < end_time
    AND NEW.end_time > start_time;

    IF conflict_count > 0 THEN
        RAISE EXCEPTION 'Truck already has an overlapping dispatch';
    END IF;

    RETURN NEW;
END;
$$;


--
-- Name: trg_fn_update_hours(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_fn_update_hours() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE DRIVER
    SET weekly_hours_logged = weekly_hours_logged + (EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 3600)
    WHERE driver_id = NEW.driver_id;

    UPDATE ASSISTANT
    SET weekly_hours_logged = weekly_hours_logged + (EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time)) / 3600)
    WHERE assistant_id = NEW.assistant_id;

    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: assistant; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assistant (
    assistant_id character varying(10) NOT NULL,
    assistant_name character varying(100) NOT NULL,
    weekly_hours_logged numeric(5,2) DEFAULT 0 NOT NULL,
    CONSTRAINT assistant_weekly_hours_logged_check CHECK ((weekly_hours_logged <= 60.00))
);


--
-- Name: city; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.city (
    city_id character varying(10) NOT NULL,
    city_name character varying(50) NOT NULL,
    has_rail_station boolean DEFAULT false NOT NULL
);


--
-- Name: customer; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer (
    customer_id character varying(10) NOT NULL,
    customer_name character varying(100) NOT NULL,
    delivery_address character varying(255) NOT NULL,
    phone_number character varying(15) NOT NULL,
    email character varying(100),
    city_id character varying(10) NOT NULL,
    password character varying(255) NOT NULL
);


--
-- Name: customer_order; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_order (
    order_id character varying(10) NOT NULL,
    customer_id character varying(10) NOT NULL,
    amount numeric(10,2) DEFAULT 0 NOT NULL,
    placement_date date NOT NULL,
    delivery_date date NOT NULL,
    status character varying(20) DEFAULT 'placed'::character varying NOT NULL,
    CONSTRAINT chk_delivery_lead_time CHECK ((delivery_date >= (placement_date + '7 days'::interval))),
    CONSTRAINT customer_order_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT customer_order_status_check CHECK (((status)::text = ANY (ARRAY[('placed'::character varying)::text, ('scheduled'::character varying)::text, ('dispatched'::character varying)::text, ('delivered'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: driver; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.driver (
    driver_id character varying(10) NOT NULL,
    driver_name character varying(100) NOT NULL,
    weekly_hours_logged numeric(5,2) DEFAULT 0 NOT NULL,
    CONSTRAINT driver_weekly_hours_logged_check CHECK ((weekly_hours_logged <= 40.00))
);


--
-- Name: order_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_item (
    order_id character varying(10) NOT NULL,
    product_id character varying(10) NOT NULL,
    quantity integer NOT NULL,
    price numeric(10,2) NOT NULL,
    CONSTRAINT order_item_price_check CHECK ((price >= (0)::numeric)),
    CONSTRAINT order_item_quantity_check CHECK ((quantity > 0))
);


--
-- Name: order_travel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_travel (
    order_id character varying(10) NOT NULL,
    trip_id character varying(10) NOT NULL,
    route_id character varying(10) NOT NULL
);


--
-- Name: order_trip_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_trip_item (
    order_id character varying(10) NOT NULL,
    trip_id character varying(10) NOT NULL,
    product_id character varying(10) NOT NULL,
    quantity integer NOT NULL,
    space_per_unit numeric(6,2) NOT NULL,
    reservation_active boolean DEFAULT true NOT NULL,
    CONSTRAINT order_trip_item_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT order_trip_item_space_per_unit_check CHECK ((space_per_unit > (0)::numeric))
);


--
-- Name: product; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product (
    product_id character varying(10) NOT NULL,
    product_name character varying(100) NOT NULL,
    space_consumption numeric(6,2) NOT NULL,
    price numeric(10,2) NOT NULL,
    CONSTRAINT product_price_check CHECK ((price >= (0)::numeric)),
    CONSTRAINT product_space_consumption_check CHECK ((space_consumption > (0)::numeric))
);


--
-- Name: route; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.route (
    route_id character varying(10) NOT NULL,
    store_id character varying(10) NOT NULL,
    city character varying(50) NOT NULL,
    coverage_area character varying(255) NOT NULL,
    max_delivery_time numeric(5,2) NOT NULL,
    CONSTRAINT route_max_delivery_time_check CHECK ((max_delivery_time > (0)::numeric))
);


--
-- Name: staff_user; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_user (
    staff_id character varying(10) NOT NULL,
    staff_name character varying(100) NOT NULL,
    email character varying(100) NOT NULL,
    password character varying(255) NOT NULL,
    role character varying(20) NOT NULL,
    CONSTRAINT staff_user_role_check CHECK (((role)::text = ANY (ARRAY[('ADMIN'::character varying)::text, ('DISPATCHER'::character varying)::text, ('STORE_MANAGER'::character varying)::text, ('DRIVER'::character varying)::text])))
);


--
-- Name: store; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store (
    store_id character varying(10) NOT NULL,
    city_id character varying(10) NOT NULL
);


--
-- Name: train; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.train (
    train_id character varying(10) NOT NULL,
    size numeric(8,2) NOT NULL,
    capacity_per_product numeric(8,2) NOT NULL
);


--
-- Name: train_schedule; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.train_schedule (
    trip_id character varying(10) NOT NULL,
    city_id character varying(10) NOT NULL,
    departure_datetime timestamp without time zone NOT NULL,
    arrival_datetime timestamp without time zone NOT NULL,
    train_id character varying(10) NOT NULL,
    store_id character varying(10) NOT NULL,
    available_capacity numeric(8,2) NOT NULL,
    allocated_capacity numeric(10,2) NOT NULL,
    CONSTRAINT chk_train_times CHECK ((arrival_datetime > departure_datetime)),
    CONSTRAINT chk_trip_capacity_bounds CHECK (((allocated_capacity >= (0)::numeric) AND (available_capacity <= allocated_capacity))),
    CONSTRAINT train_schedule_available_capacity_check CHECK ((available_capacity >= (0)::numeric))
);


--
-- Name: COLUMN train_schedule.allocated_capacity; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.train_schedule.allocated_capacity IS 'Fixed capacity allocated to this trip. Migration baseline = uploaded remaining capacity plus known active allocations; historical deduction errors are not inferred or corrected.';


--
-- Name: truck; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.truck (
    truck_id character varying(10) NOT NULL,
    store_id character varying(10) NOT NULL,
    plate_number character varying(20) NOT NULL,
    capacity numeric(8,2) NOT NULL
);


--
-- Name: truck_dispatch; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.truck_dispatch (
    dispatch_id character varying(10) NOT NULL,
    truck_id character varying(10) NOT NULL,
    route_id character varying(10) NOT NULL,
    driver_id character varying(10) NOT NULL,
    assistant_id character varying(10) NOT NULL,
    start_time timestamp without time zone NOT NULL,
    end_time timestamp without time zone NOT NULL,
    CONSTRAINT chk_dispatch_times CHECK ((end_time > start_time))
);


--
-- Name: view_city_route_sales; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.view_city_route_sales AS
 SELECT c.city_name,
    r.route_id,
    r.coverage_area,
    count(DISTINCT co.order_id) AS orders_count,
    sum(((a.quantity)::numeric * oi.price)) AS route_revenue
   FROM ((((((public.customer_order co
     JOIN public.order_trip_item a USING (order_id))
     JOIN public.order_item oi ON ((((oi.order_id)::text = (a.order_id)::text) AND ((oi.product_id)::text = (a.product_id)::text))))
     JOIN public.order_travel ot ON ((((ot.order_id)::text = (a.order_id)::text) AND ((ot.trip_id)::text = (a.trip_id)::text))))
     JOIN public.route r USING (route_id))
     JOIN public.store s ON (((s.store_id)::text = (r.store_id)::text)))
     JOIN public.city c ON (((c.city_id)::text = (s.city_id)::text)))
  WHERE (((co.status)::text <> 'cancelled'::text) AND a.reservation_active)
  GROUP BY c.city_name, r.route_id, r.coverage_area
  ORDER BY c.city_name, (sum(((a.quantity)::numeric * oi.price))) DESC;


--
-- Name: view_driver_assistant_hours; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.view_driver_assistant_hours AS
 SELECT 'Driver'::text AS role,
    d.driver_id AS person_id,
    d.driver_name AS name,
    d.weekly_hours_logged AS total_hours
   FROM public.driver d
UNION ALL
 SELECT 'Assistant'::text AS role,
    a.assistant_id AS person_id,
    a.assistant_name AS name,
    a.weekly_hours_logged AS total_hours
   FROM public.assistant a
  ORDER BY 1, 4 DESC;


--
-- Name: view_quarterly_sales; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.view_quarterly_sales AS
 SELECT EXTRACT(year FROM co.placement_date) AS sales_year,
    EXTRACT(quarter FROM co.placement_date) AS sales_quarter,
    count(DISTINCT co.order_id) AS total_orders,
    sum(oi.quantity) AS total_units_sold,
    sum(((oi.quantity)::numeric * oi.price)) AS total_revenue
   FROM (public.customer_order co
     JOIN public.order_item oi ON (((co.order_id)::text = (oi.order_id)::text)))
  WHERE ((co.status)::text <> 'cancelled'::text)
  GROUP BY (EXTRACT(year FROM co.placement_date)), (EXTRACT(quarter FROM co.placement_date))
  ORDER BY (EXTRACT(year FROM co.placement_date)) DESC, (EXTRACT(quarter FROM co.placement_date)) DESC;


--
-- Name: view_truck_utilization; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.view_truck_utilization AS
 SELECT t.truck_id,
    t.plate_number,
    EXTRACT(year FROM td.start_time) AS year,
    EXTRACT(month FROM td.start_time) AS month,
    count(td.dispatch_id) AS total_trips,
    round(sum((EXTRACT(epoch FROM (td.end_time - td.start_time)) / (3600)::numeric)), 2) AS total_hours_operated
   FROM (public.truck t
     LEFT JOIN public.truck_dispatch td ON (((t.truck_id)::text = (td.truck_id)::text)))
  GROUP BY t.truck_id, t.plate_number, (EXTRACT(year FROM td.start_time)), (EXTRACT(month FROM td.start_time))
  ORDER BY t.truck_id, (EXTRACT(year FROM td.start_time)), (EXTRACT(month FROM td.start_time));


--
-- Data for Name: assistant; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.assistant (assistant_id, assistant_name, weekly_hours_logged) FROM stdin;
AST08	Buddhika Senanayake	5.00
AST01	Ruwan Bandara	10.00
AST02	Priyantha Jayasuriya	10.00
AST03	Nuwan Dissanayake	10.00
AST04	Chandana Silva	10.00
AST05	Lasith Ekanayake	10.00
AST06	Dinesh Rajapaksa	10.00
AST07	Ranjith Perera	10.00
\.


--
-- Data for Name: city; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.city (city_id, city_name, has_rail_station) FROM stdin;
KDY	Kandy	f
CMB	Colombo	t
NEG	Negombo	t
GAL	Galle	t
MAT	Matara	t
JAF	Jaffna	t
TRN	Trincomalee	t
\.


--
-- Data for Name: customer; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customer (customer_id, customer_name, delivery_address, phone_number, email, city_id, password) FROM stdin;
CUST01	Nimal Perera	45 Galle Road, Colombo 03	0795822412	nimal.perera@example.com	CMB	hashed_pw_placeholder
CUST02	Kamala Fernando	12 Duplication Road, Colombo 04	0724942603	kamala.fernando@example.com	CMB	hashed_pw_placeholder
CUST03	Ruwan Jayasuriya	78 High Level Road, Nugegoda	0713356886	ruwan.jayasuriya@example.com	CMB	hashed_pw_placeholder
CUST04	Chathurika Silva	23 Baseline Road, Colombo 09	0746913810	chathurika.silva@example.com	CMB	hashed_pw_placeholder
CUST05	Sampath Rathnayake	56 Chilaw Road, Negombo	0742868828	sampath.rathnayake@example.com	NEG	hashed_pw_placeholder
CUST06	Anusha Wickramasinghe	34 Poruthota Road, Negombo	0739958838	anusha.wickramasinghe@example.com	NEG	hashed_pw_placeholder
CUST07	Dilshan Gunawardena	9 Airport Road, Katunayake	0728728463	dilshan.gunawardena@example.com	NEG	hashed_pw_placeholder
CUST08	Manori Dissanayake	67 Main Street, Ja-Ela	0723756669	manori.dissanayake@example.com	NEG	hashed_pw_placeholder
CUST09	Tharindu Bandara	15 Matara Road, Galle	0783197857	tharindu.bandara@example.com	GAL	hashed_pw_placeholder
CUST10	Ishara Weerasinghe	88 Lighthouse Street, Galle Fort	0721668732	ishara.weerasinghe@example.com	GAL	hashed_pw_placeholder
CUST11	Chamila Ekanayake	21 Wackwella Road, Galle	0789254563	chamila.ekanayake@example.com	GAL	hashed_pw_placeholder
CUST12	Prasanna Kariyawasam	40 Beach Road, Unawatuna	0766629388	prasanna.kariyawasam@example.com	GAL	hashed_pw_placeholder
CUST13	Nadeeka Gamage	11 Station Road, Matara	0714265799	nadeeka.gamage@example.com	MAT	hashed_pw_placeholder
CUST14	Roshan Abeysekara	63 Deniyaya Road, Matara	0713999315	roshan.abeysekara@example.com	MAT	hashed_pw_placeholder
CUST15	Sanduni Mendis	27 Beach Road, Weligama	0722575562	sanduni.mendis@example.com	MAT	hashed_pw_placeholder
CUST16	Kasun Rajapaksa	5 Hospital Road, Jaffna	0739345092	kasun.rajapaksa@example.com	JAF	hashed_pw_placeholder
CUST17	Vidya Thillainathan	19 KKS Road, Jaffna	0741227216	vidya.thillainathan@example.com	JAF	hashed_pw_placeholder
CUST18	Ajith Kumara	31 Nelson Street, Jaffna	0777827638	ajith.kumara@example.com	JAF	hashed_pw_placeholder
CUST19	Harshani Wijesekara	8 Dockyard Road, Trincomalee	0790801586	harshani.wijesekara@example.com	TRN	hashed_pw_placeholder
CUST20	Lakshan Peiris	44 Nilaveli Road, Trincomalee	0713561597	lakshan.peiris@example.com	TRN	hashed_pw_placeholder
CUST1381F2	Test User Two	456 New Street, Colombo	0779876543	testuser2@example.com	CMB	$2a$10$a2UldLs1A4Tb7Dta3txSt.Hfkyq4ICO5mRRaj10wedQ.bfOMp8jh2
CUST3D6E3C	malith dilshan bandara	hungmpola	0762305935	bmalith082@gmail.com	CMB	$2a$10$suOhDQfFd2vIEwjYnVRHD.o5oGlI/H933xjC4yqlXkYbmwzhpTQbC
CUSTB54F44	malith dilshan bandara	hungmpola	12131564123	bmalith083@gmail.com	CMB	$2a$10$K31SkfyQ/AOtSrf4GDFopef1hzu3kQ2UT6796EcuoQDdiDhttM.vO
CUSTF42011	malith dilshan bandara	hungmpola	1234567890	s@gmail.com	CMB	$2a$10$Fl6ku4MNot0zSRJpUl7KZOoYgn2SoiRLcjf.AQvaTS8q47zBy1fHC
\.


--
-- Data for Name: customer_order; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customer_order (order_id, customer_id, amount, placement_date, delivery_date, status) FROM stdin;
ORD04	CUST04	840.00	2026-08-04	2026-08-17	delivered
ORD05	CUST05	1450.00	2026-08-03	2026-08-10	placed
ORD06	CUST06	570.00	2026-08-15	2026-08-27	scheduled
ORD07	CUST07	5110.00	2026-08-03	2026-08-12	dispatched
ORD08	CUST08	630.00	2026-08-02	2026-08-12	delivered
ORD09	CUST09	3500.00	2026-08-03	2026-08-13	placed
ORD10	CUST10	1700.00	2026-08-09	2026-08-18	scheduled
ORD11	CUST11	1050.00	2026-08-13	2026-08-25	dispatched
ORD12	CUST12	240.00	2026-08-02	2026-08-10	delivered
ORD13	CUST13	2930.00	2026-08-13	2026-08-26	placed
ORD14	CUST14	1650.00	2026-08-04	2026-08-15	scheduled
ORD15	CUST15	380.00	2026-08-10	2026-08-20	dispatched
ORD16	CUST16	2070.00	2026-08-16	2026-08-23	delivered
ORD17	CUST17	3670.00	2026-08-02	2026-08-12	placed
ORD18	CUST18	1760.00	2026-08-16	2026-08-25	scheduled
ORD19	CUST19	1840.00	2026-08-10	2026-08-23	dispatched
ORD20	CUST20	3800.00	2026-08-03	2026-08-15	delivered
ORD21	CUST01	2545.00	2026-08-01	2026-08-09	placed
ORD22	CUST02	560.00	2026-08-09	2026-08-23	scheduled
ORD23	CUST03	320.00	2026-08-16	2026-08-29	dispatched
ORD24	CUST04	430.00	2026-08-14	2026-08-27	delivered
ORD25	CUST05	1560.00	2026-08-11	2026-08-19	placed
ORD26	CUST06	3600.00	2026-08-14	2026-08-23	scheduled
ORD27	CUST07	840.00	2026-08-01	2026-08-09	dispatched
ORD28	CUST08	840.00	2026-08-07	2026-08-20	delivered
ORD29	CUST09	2110.00	2026-08-09	2026-08-23	placed
ORD30	CUST10	3800.00	2026-08-10	2026-08-20	scheduled
ORD31	CUST11	1690.00	2026-08-02	2026-08-09	dispatched
ORD32	CUST12	4290.00	2026-08-03	2026-08-11	delivered
ORD33	CUST13	2580.00	2026-08-14	2026-08-26	placed
ORD34	CUST14	400.00	2026-08-05	2026-08-16	scheduled
ORD35	CUST15	1240.00	2026-08-03	2026-08-13	dispatched
ORD36	CUST16	1650.00	2026-08-15	2026-08-26	delivered
ORD37	CUST17	1700.00	2026-08-09	2026-08-17	placed
ORD38	CUST18	4950.00	2026-08-10	2026-08-20	scheduled
ORD39	CUST19	1635.00	2026-08-03	2026-08-16	dispatched
ORD40	CUST20	1860.00	2026-08-15	2026-08-28	delivered
ORD726735F	CUST01	170.00	2026-09-05	2026-09-20	placed
ORDAE93AD5	CUST01	170.00	2026-09-05	2026-09-20	placed
ORD8F5783D	CUST01	85.00	2026-09-05	2026-09-20	placed
ORD7467861	CUST1381F2	85.00	2026-09-05	2026-09-25	placed
ORD01	CUST01	2400.00	2026-08-07	2026-08-20	delivered
ORDFAC427B	CUST01	210.00	2026-09-13	2026-09-24	placed
ORD19FBE4B	CUST1381F2	320.00	2026-09-13	2026-09-29	placed
ORDDE125B4	CUST1381F2	280.00	2026-09-13	2026-09-24	placed
ORDB807336	CUST1381F2	85.00	2026-09-13	2026-10-02	placed
ORD20F6460	CUST1381F2	280.00	2026-09-15	2026-10-09	placed
ORDCCCDC8E	CUST1381F2	150.00	2026-09-15	2026-09-24	placed
ORDA5CDEF2	CUST1381F2	320.00	2026-09-26	2026-10-10	placed
ORDDBA68AD	CUST1381F2	250.00	2026-09-26	2026-10-10	placed
ORD9F09EA3	CUST3D6E3C	780.00	2026-09-26	2026-10-08	placed
ORDA0A160B	CUST3D6E3C	250.00	2026-09-26	2026-10-10	placed
ORD9C2F4B5	CUST3D6E3C	280.00	2026-09-29	2026-10-10	placed
ORD02	CUST02	1130.00	2026-08-06	2026-08-19	dispatched
ORD850462F	CUSTB54F44	640.00	2026-09-29	2026-10-14	placed
ORD8BC6F11	CUSTB54F44	640.00	2026-09-29	2026-10-14	placed
ORD03	CUST03	1020.00	2026-08-13	2026-08-21	placed
ORDDEC81AF	CUST3D6E3C	85.00	2026-10-05	2026-10-22	placed
ORD52B6385	CUST3D6E3C	280.00	2026-10-06	2026-10-15	dispatched
\.


--
-- Data for Name: driver; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.driver (driver_id, driver_name, weekly_hours_logged) FROM stdin;
DRV08	Mahesh Kariyawasam	5.00
DRV01	Sunil Perera	10.00
DRV02	Kamal Silva	10.00
DRV03	Nimal Fernando	10.00
DRV04	Ajith Kumara	10.00
DRV05	Chaminda Rathnayake	10.00
DRV06	Sarath Wijesinghe	10.00
DRV07	Rohan Gunasekara	10.00
\.


--
-- Data for Name: order_item; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_item (order_id, product_id, quantity, price) FROM stdin;
ORD01	PRD08	5	480.00
ORD02	PRD05	2	250.00
ORD02	PRD03	3	210.00
ORD03	PRD14	5	90.00
ORD03	PRD06	3	190.00
ORD04	PRD09	3	280.00
ORD05	PRD04	1	780.00
ORD05	PRD13	2	210.00
ORD05	PRD05	1	250.00
ORD06	PRD06	3	190.00
ORD07	PRD12	4	340.00
ORD07	PRD04	4	780.00
ORD07	PRD03	3	210.00
ORD08	PRD13	3	210.00
ORD09	PRD15	2	690.00
ORD09	PRD12	4	340.00
ORD09	PRD06	4	190.00
ORD10	PRD12	5	340.00
ORD11	PRD03	5	210.00
ORD12	PRD11	2	120.00
ORD13	PRD08	5	480.00
ORD13	PRD09	1	280.00
ORD13	PRD05	1	250.00
ORD14	PRD03	1	210.00
ORD14	PRD08	3	480.00
ORD15	PRD06	2	190.00
ORD16	PRD15	3	690.00
ORD17	PRD02	4	320.00
ORD17	PRD15	1	690.00
ORD17	PRD12	5	340.00
ORD18	PRD09	5	280.00
ORD18	PRD14	4	90.00
ORD19	PRD11	5	120.00
ORD19	PRD06	4	190.00
ORD19	PRD08	1	480.00
ORD20	PRD10	5	760.00
ORD21	PRD11	1	120.00
ORD21	PRD01	1	85.00
ORD21	PRD04	3	780.00
ORD22	PRD09	2	280.00
ORD23	PRD02	1	320.00
ORD24	PRD14	1	90.00
ORD24	PRD12	1	340.00
ORD25	PRD04	2	780.00
ORD26	PRD08	1	480.00
ORD26	PRD04	4	780.00
ORD27	PRD03	4	210.00
ORD28	PRD03	4	210.00
ORD29	PRD07	5	150.00
ORD29	PRD12	4	340.00
ORD30	PRD10	5	760.00
ORD31	PRD08	2	480.00
ORD31	PRD09	1	280.00
ORD31	PRD14	5	90.00
ORD32	PRD14	1	90.00
ORD32	PRD04	5	780.00
ORD32	PRD07	2	150.00
ORD33	PRD04	3	780.00
ORD33	PRD11	2	120.00
ORD34	PRD06	1	190.00
ORD34	PRD13	1	210.00
ORD35	PRD05	1	250.00
ORD35	PRD03	2	210.00
ORD35	PRD06	3	190.00
ORD36	PRD13	1	210.00
ORD36	PRD11	5	120.00
ORD36	PRD09	3	280.00
ORD37	PRD12	5	340.00
ORD38	PRD06	3	190.00
ORD38	PRD04	5	780.00
ORD38	PRD11	4	120.00
ORD39	PRD01	3	85.00
ORD39	PRD15	2	690.00
ORD40	PRD01	2	85.00
ORD40	PRD02	5	320.00
ORD40	PRD14	1	90.00
ORD726735F	PRD01	2	85.00
ORDAE93AD5	PRD01	2	85.00
ORD8F5783D	PRD01	1	85.00
ORD7467861	PRD01	1	85.00
ORDFAC427B	PRD03	1	210.00
ORD19FBE4B	PRD02	1	320.00
ORDDE125B4	PRD09	1	280.00
ORDB807336	PRD01	1	85.00
ORD20F6460	PRD09	1	280.00
ORDCCCDC8E	PRD07	1	150.00
ORDA5CDEF2	PRD02	1	320.00
ORDDBA68AD	PRD05	1	250.00
ORD9F09EA3	PRD04	1	780.00
ORDA0A160B	PRD05	1	250.00
ORD9C2F4B5	PRD09	1	280.00
ORD850462F	PRD02	2	320.00
ORD8BC6F11	PRD02	2	320.00
ORDDEC81AF	PRD01	1	85.00
ORD52B6385	PRD09	1	280.00
\.


--
-- Data for Name: order_travel; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_travel (order_id, trip_id, route_id) FROM stdin;
ORD01	TRP07	RT01
ORD02	TRP01	RT01
ORD03	TRP01	RT02
ORD04	TRP07	RT01
ORD05	TRP08	RT04
ORD06	TRP02	RT04
ORD07	TRP02	RT04
ORD08	TRP08	RT04
ORD09	TRP09	RT05
ORD10	TRP09	RT06
ORD11	TRP09	RT05
ORD12	TRP09	RT05
ORD13	TRP10	RT08
ORD14	TRP04	RT07
ORD15	TRP04	RT08
ORD16	TRP11	RT09
ORD17	TRP05	RT09
ORD18	TRP05	RT09
ORD19	TRP06	RT10
ORD20	TRP06	RT10
ORD21	TRP01	RT01
ORD22	TRP07	RT01
ORD23	TRP07	RT02
ORD24	TRP01	RT02
ORD25	TRP08	RT03
ORD26	TRP02	RT03
ORD27	TRP08	RT04
ORD28	TRP02	RT04
ORD29	TRP03	RT05
ORD30	TRP03	RT06
ORD31	TRP03	RT05
ORD32	TRP03	RT05
ORD33	TRP10	RT08
ORD34	TRP10	RT07
ORD35	TRP10	RT07
ORD36	TRP05	RT09
ORD37	TRP05	RT09
ORD38	TRP11	RT09
ORD39	TRP12	RT10
ORD40	TRP12	RT10
ORD726735F	TRP07	RT01
ORDAE93AD5	TRP07	RT01
ORD8F5783D	TRP07	RT01
ORD7467861	TRP07	RT01
ORDFAC427B	TRP07	RT01
ORD19FBE4B	TRP07	RT01
ORDDE125B4	TRP07	RT01
ORDB807336	TRP07	RT01
ORD20F6460	TRP07	RT01
ORDCCCDC8E	TRP07	RT01
ORDA5CDEF2	TRP07	RT01
ORDDBA68AD	TRP07	RT01
ORD9F09EA3	TRP07	RT01
ORDA0A160B	TRP07	RT01
ORD9C2F4B5	TRP07	RT01
ORD850462F	TRP07	RT01
ORD8BC6F11	TRP07	RT01
ORDDEC81AF	TRP07	RT01
ORD52B6385	DM0101	RT02
\.


--
-- Data for Name: order_trip_item; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_trip_item (order_id, trip_id, product_id, quantity, space_per_unit, reservation_active) FROM stdin;
ORD01	TRP07	PRD08	5	0.50	t
ORD02	TRP01	PRD05	2	0.60	t
ORD02	TRP01	PRD03	3	0.30	t
ORD03	TRP01	PRD14	5	0.20	t
ORD03	TRP01	PRD06	3	0.25	t
ORD04	TRP07	PRD09	3	0.60	t
ORD05	TRP08	PRD04	1	0.40	t
ORD05	TRP08	PRD13	2	0.10	t
ORD05	TRP08	PRD05	1	0.60	t
ORD06	TRP02	PRD06	3	0.25	t
ORD07	TRP02	PRD12	4	0.30	t
ORD07	TRP02	PRD04	4	0.40	t
ORD07	TRP02	PRD03	3	0.30	t
ORD08	TRP08	PRD13	3	0.10	t
ORD09	TRP09	PRD15	2	0.35	t
ORD09	TRP09	PRD12	4	0.30	t
ORD09	TRP09	PRD06	4	0.25	t
ORD10	TRP09	PRD12	5	0.30	t
ORD11	TRP09	PRD03	5	0.30	t
ORD12	TRP09	PRD11	2	0.15	t
ORD13	TRP10	PRD08	5	0.50	t
ORD13	TRP10	PRD09	1	0.60	t
ORD13	TRP10	PRD05	1	0.60	t
ORD14	TRP04	PRD03	1	0.30	t
ORD14	TRP04	PRD08	3	0.50	t
ORD15	TRP04	PRD06	2	0.25	t
ORD16	TRP11	PRD15	3	0.35	t
ORD17	TRP05	PRD02	4	0.35	t
ORD17	TRP05	PRD15	1	0.35	t
ORD17	TRP05	PRD12	5	0.30	t
ORD18	TRP05	PRD09	5	0.60	t
ORD18	TRP05	PRD14	4	0.20	t
ORD19	TRP06	PRD11	5	0.15	t
ORD19	TRP06	PRD06	4	0.25	t
ORD19	TRP06	PRD08	1	0.50	t
ORD20	TRP06	PRD10	5	0.40	t
ORD21	TRP01	PRD11	1	0.15	t
ORD21	TRP01	PRD01	1	0.20	t
ORD21	TRP01	PRD04	3	0.40	t
ORD22	TRP07	PRD09	2	0.60	t
ORD23	TRP07	PRD02	1	0.35	t
ORD24	TRP01	PRD14	1	0.20	t
ORD24	TRP01	PRD12	1	0.30	t
ORD25	TRP08	PRD04	2	0.40	t
ORD26	TRP02	PRD08	1	0.50	t
ORD26	TRP02	PRD04	4	0.40	t
ORD27	TRP08	PRD03	4	0.30	t
ORD28	TRP02	PRD03	4	0.30	t
ORD29	TRP03	PRD07	5	0.20	t
ORD29	TRP03	PRD12	4	0.30	t
ORD30	TRP03	PRD10	5	0.40	t
ORD31	TRP03	PRD08	2	0.50	t
ORD31	TRP03	PRD09	1	0.60	t
ORD31	TRP03	PRD14	5	0.20	t
ORD32	TRP03	PRD14	1	0.20	t
ORD32	TRP03	PRD04	5	0.40	t
ORD32	TRP03	PRD07	2	0.20	t
ORD33	TRP10	PRD04	3	0.40	t
ORD33	TRP10	PRD11	2	0.15	t
ORD34	TRP10	PRD06	1	0.25	t
ORD34	TRP10	PRD13	1	0.10	t
ORD35	TRP10	PRD05	1	0.60	t
ORD35	TRP10	PRD03	2	0.30	t
ORD35	TRP10	PRD06	3	0.25	t
ORD36	TRP05	PRD13	1	0.10	t
ORD36	TRP05	PRD11	5	0.15	t
ORD36	TRP05	PRD09	3	0.60	t
ORD37	TRP05	PRD12	5	0.30	t
ORD38	TRP11	PRD06	3	0.25	t
ORD38	TRP11	PRD04	5	0.40	t
ORD38	TRP11	PRD11	4	0.15	t
ORD39	TRP12	PRD01	3	0.20	t
ORD39	TRP12	PRD15	2	0.35	t
ORD40	TRP12	PRD01	2	0.20	t
ORD40	TRP12	PRD02	5	0.35	t
ORD40	TRP12	PRD14	1	0.20	t
ORD726735F	TRP07	PRD01	2	0.20	t
ORDAE93AD5	TRP07	PRD01	2	0.20	t
ORD8F5783D	TRP07	PRD01	1	0.20	t
ORD7467861	TRP07	PRD01	1	0.20	t
ORDFAC427B	TRP07	PRD03	1	0.30	t
ORD19FBE4B	TRP07	PRD02	1	0.35	t
ORDDE125B4	TRP07	PRD09	1	0.60	t
ORDB807336	TRP07	PRD01	1	0.20	t
ORD20F6460	TRP07	PRD09	1	0.60	t
ORDCCCDC8E	TRP07	PRD07	1	0.20	t
ORDA5CDEF2	TRP07	PRD02	1	0.35	t
ORDDBA68AD	TRP07	PRD05	1	0.60	t
ORD9F09EA3	TRP07	PRD04	1	0.40	t
ORDA0A160B	TRP07	PRD05	1	0.60	t
ORD9C2F4B5	TRP07	PRD09	1	0.60	t
ORD850462F	TRP07	PRD02	2	0.35	t
ORD8BC6F11	TRP07	PRD02	2	0.35	t
ORDDEC81AF	TRP07	PRD01	1	0.20	t
ORD52B6385	DM0101	PRD09	1	0.60	t
\.


--
-- Data for Name: product; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.product (product_id, product_name, space_consumption, price) FROM stdin;
PRD01	Sunlight Soap Bar	0.20	85.00
PRD02	Astra Margarine 500g	0.35	320.00
PRD03	Munchee Cream Crackers	0.30	210.00
PRD04	Anchor Milk Powder 400g	0.40	780.00
PRD05	Elephant House Cream Soda 1.5L	0.60	250.00
PRD06	Maliban Chocolate Biscuits	0.25	190.00
PRD07	Dettol Antiseptic Soap	0.20	150.00
PRD08	Persil Detergent Powder 1kg	0.50	480.00
PRD09	Coca-Cola 1.5L Bottle	0.60	280.00
PRD10	Highland Milk Powder 400g	0.40	760.00
PRD11	Prima Noodles Pack	0.15	120.00
PRD12	Fairy Dishwash Liquid 500ml	0.30	340.00
PRD13	Signal Toothpaste 120g	0.10	210.00
PRD14	Lifebuoy Soap Bar	0.20	90.00
PRD15	Nestomalt 400g	0.35	690.00
\.


--
-- Data for Name: route; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.route (route_id, store_id, city, coverage_area, max_delivery_time) FROM stdin;
RT01	STR-CMB	Colombo	Colombo Fort - Pettah	2.50
RT02	STR-CMB	Colombo	Dehiwala - Mount Lavinia	3.00
RT03	STR-NEG	Negombo	Negombo Town - Katunayake	2.00
RT04	STR-NEG	Negombo	Seeduwa - Ja-Ela	2.50
RT05	STR-GAL	Galle	Galle Fort - Unawatuna	2.00
RT06	STR-GAL	Galle	Hikkaduwa - Ambalangoda	3.00
RT07	STR-MAT	Matara	Matara Town - Weligama	2.50
RT08	STR-MAT	Matara	Dikwella - Tangalle	3.50
RT09	STR-JAF	Jaffna	Jaffna Town - Nallur	2.00
RT10	STR-TRN	Trincomalee	Trincomalee Town - Nilaveli	3.00
\.


--
-- Data for Name: staff_user; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.staff_user (staff_id, staff_name, email, password, role) FROM stdin;
STAFF001	Admin User	admin@kandypack.com	$2b$10$S75VtashGN15VRj26M.nGeiY7g138nZnk3A5TKPcImiMoOhmS.6py	ADMIN
STF136B1FD	Dispatcher One	dispatcher1@kandypack.com	$2a$10$W3W9g.W8sC4vPNfMknVSBu0L5SESysd8EaEHDcVX9hSdMOfOJsisa	DISPATCHER
\.


--
-- Data for Name: store; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.store (store_id, city_id) FROM stdin;
STR-CMB	CMB
STR-NEG	NEG
STR-GAL	GAL
STR-MAT	MAT
STR-JAF	JAF
STR-TRN	TRN
\.


--
-- Data for Name: train; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.train (train_id, size, capacity_per_product) FROM stdin;
TRN01	500.00	1.00
TRN02	400.00	1.00
TRN03	600.00	1.00
DMTRAIN001	300.00	1.00
DMTRAIN002	300.00	1.00
DMTRAIN003	300.00	1.00
DMTRAIN004	300.00	1.00
DMTRAIN005	300.00	1.00
DMTRAIN006	300.00	1.00
\.


--
-- Data for Name: train_schedule; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.train_schedule (trip_id, city_id, departure_datetime, arrival_datetime, train_id, store_id, available_capacity, allocated_capacity) FROM stdin;
DM0101	CMB	2026-10-07 08:00:00	2026-10-07 14:00:00	DMTRAIN001	STR-CMB	299.40	300.00
TRP09	GAL	2026-08-17 08:00:00	2026-08-17 14:00:00	TRN03	STR-GAL	293.80	300.00
TRP04	MAT	2026-08-07 08:00:00	2026-08-07 14:00:00	TRN01	STR-MAT	297.70	300.00
TRP06	TRN	2026-08-11 08:00:00	2026-08-11 14:00:00	TRN03	STR-TRN	295.75	300.00
TRP01	CMB	2026-08-01 08:00:00	2026-08-01 14:00:00	TRN01	STR-CMB	294.10	300.00
TRP08	NEG	2026-08-15 08:00:00	2026-08-15 14:00:00	TRN02	STR-NEG	296.50	300.00
TRP02	NEG	2026-08-03 08:00:00	2026-08-03 14:00:00	TRN02	STR-NEG	292.25	300.00
TRP03	GAL	2026-08-05 08:00:00	2026-08-05 14:00:00	TRN03	STR-GAL	290.60	300.00
TRP10	MAT	2026-08-19 08:00:00	2026-08-19 14:00:00	TRN01	STR-MAT	292.50	300.00
TRP05	JAF	2026-08-09 08:00:00	2026-08-09 14:00:00	TRN02	STR-JAF	288.80	300.00
TRP11	JAF	2026-08-21 08:00:00	2026-08-21 14:00:00	TRN02	STR-JAF	295.60	300.00
TRP12	TRN	2026-08-23 08:00:00	2026-08-23 14:00:00	TRN03	STR-TRN	296.35	300.00
TRP07	CMB	2026-08-13 08:00:00	2026-08-13 14:00:00	TRN01	STR-CMB	286.55	300.00
DM0102	CMB	2026-10-08 08:00:00	2026-10-08 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0103	CMB	2026-10-09 08:00:00	2026-10-09 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0104	CMB	2026-10-10 08:00:00	2026-10-10 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0105	CMB	2026-10-11 08:00:00	2026-10-11 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0106	CMB	2026-10-12 08:00:00	2026-10-12 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0107	CMB	2026-10-13 08:00:00	2026-10-13 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0108	CMB	2026-10-14 08:00:00	2026-10-14 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0109	CMB	2026-10-15 08:00:00	2026-10-15 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0110	CMB	2026-10-16 08:00:00	2026-10-16 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0111	CMB	2026-10-17 08:00:00	2026-10-17 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0112	CMB	2026-10-18 08:00:00	2026-10-18 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0113	CMB	2026-10-19 08:00:00	2026-10-19 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0114	CMB	2026-10-20 08:00:00	2026-10-20 14:00:00	DMTRAIN001	STR-CMB	300.00	300.00
DM0201	GAL	2026-10-07 08:00:00	2026-10-07 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0202	GAL	2026-10-08 08:00:00	2026-10-08 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0203	GAL	2026-10-09 08:00:00	2026-10-09 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0204	GAL	2026-10-10 08:00:00	2026-10-10 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0205	GAL	2026-10-11 08:00:00	2026-10-11 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0206	GAL	2026-10-12 08:00:00	2026-10-12 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0207	GAL	2026-10-13 08:00:00	2026-10-13 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0208	GAL	2026-10-14 08:00:00	2026-10-14 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0209	GAL	2026-10-15 08:00:00	2026-10-15 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0210	GAL	2026-10-16 08:00:00	2026-10-16 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0211	GAL	2026-10-17 08:00:00	2026-10-17 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0212	GAL	2026-10-18 08:00:00	2026-10-18 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0213	GAL	2026-10-19 08:00:00	2026-10-19 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0214	GAL	2026-10-20 08:00:00	2026-10-20 14:00:00	DMTRAIN002	STR-GAL	300.00	300.00
DM0301	JAF	2026-10-07 08:00:00	2026-10-07 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0302	JAF	2026-10-08 08:00:00	2026-10-08 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0303	JAF	2026-10-09 08:00:00	2026-10-09 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0304	JAF	2026-10-10 08:00:00	2026-10-10 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0305	JAF	2026-10-11 08:00:00	2026-10-11 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0306	JAF	2026-10-12 08:00:00	2026-10-12 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0307	JAF	2026-10-13 08:00:00	2026-10-13 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0308	JAF	2026-10-14 08:00:00	2026-10-14 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0309	JAF	2026-10-15 08:00:00	2026-10-15 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0310	JAF	2026-10-16 08:00:00	2026-10-16 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0311	JAF	2026-10-17 08:00:00	2026-10-17 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0312	JAF	2026-10-18 08:00:00	2026-10-18 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0313	JAF	2026-10-19 08:00:00	2026-10-19 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0314	JAF	2026-10-20 08:00:00	2026-10-20 14:00:00	DMTRAIN003	STR-JAF	300.00	300.00
DM0401	MAT	2026-10-07 08:00:00	2026-10-07 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0402	MAT	2026-10-08 08:00:00	2026-10-08 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0403	MAT	2026-10-09 08:00:00	2026-10-09 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0404	MAT	2026-10-10 08:00:00	2026-10-10 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0405	MAT	2026-10-11 08:00:00	2026-10-11 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0406	MAT	2026-10-12 08:00:00	2026-10-12 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0407	MAT	2026-10-13 08:00:00	2026-10-13 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0408	MAT	2026-10-14 08:00:00	2026-10-14 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0409	MAT	2026-10-15 08:00:00	2026-10-15 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0410	MAT	2026-10-16 08:00:00	2026-10-16 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0411	MAT	2026-10-17 08:00:00	2026-10-17 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0412	MAT	2026-10-18 08:00:00	2026-10-18 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0413	MAT	2026-10-19 08:00:00	2026-10-19 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0414	MAT	2026-10-20 08:00:00	2026-10-20 14:00:00	DMTRAIN004	STR-MAT	300.00	300.00
DM0501	NEG	2026-10-07 08:00:00	2026-10-07 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0502	NEG	2026-10-08 08:00:00	2026-10-08 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0503	NEG	2026-10-09 08:00:00	2026-10-09 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0504	NEG	2026-10-10 08:00:00	2026-10-10 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0505	NEG	2026-10-11 08:00:00	2026-10-11 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0506	NEG	2026-10-12 08:00:00	2026-10-12 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0507	NEG	2026-10-13 08:00:00	2026-10-13 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0508	NEG	2026-10-14 08:00:00	2026-10-14 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0509	NEG	2026-10-15 08:00:00	2026-10-15 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0510	NEG	2026-10-16 08:00:00	2026-10-16 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0511	NEG	2026-10-17 08:00:00	2026-10-17 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0512	NEG	2026-10-18 08:00:00	2026-10-18 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0513	NEG	2026-10-19 08:00:00	2026-10-19 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0514	NEG	2026-10-20 08:00:00	2026-10-20 14:00:00	DMTRAIN005	STR-NEG	300.00	300.00
DM0601	TRN	2026-10-07 08:00:00	2026-10-07 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0602	TRN	2026-10-08 08:00:00	2026-10-08 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0603	TRN	2026-10-09 08:00:00	2026-10-09 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0604	TRN	2026-10-10 08:00:00	2026-10-10 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0605	TRN	2026-10-11 08:00:00	2026-10-11 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0606	TRN	2026-10-12 08:00:00	2026-10-12 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0607	TRN	2026-10-13 08:00:00	2026-10-13 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0608	TRN	2026-10-14 08:00:00	2026-10-14 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0609	TRN	2026-10-15 08:00:00	2026-10-15 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0610	TRN	2026-10-16 08:00:00	2026-10-16 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0611	TRN	2026-10-17 08:00:00	2026-10-17 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0612	TRN	2026-10-18 08:00:00	2026-10-18 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0613	TRN	2026-10-19 08:00:00	2026-10-19 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
DM0614	TRN	2026-10-20 08:00:00	2026-10-20 14:00:00	DMTRAIN006	STR-TRN	300.00	300.00
\.


--
-- Data for Name: truck; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.truck (truck_id, store_id, plate_number, capacity) FROM stdin;
TRK01	STR-CMB	WP CAB-1234	800.00
TRK02	STR-CMB	WP CAA-5678	800.00
TRK03	STR-NEG	WP CAC-4321	800.00
TRK04	STR-GAL	SP CAD-1122	800.00
TRK05	STR-GAL	SP CAE-3344	800.00
TRK06	STR-MAT	SP CAF-5566	800.00
TRK07	STR-JAF	NP CAG-7788	800.00
TRK08	STR-TRN	EP CAH-9900	800.00
\.


--
-- Data for Name: truck_dispatch; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.truck_dispatch (dispatch_id, truck_id, route_id, driver_id, assistant_id, start_time, end_time) FROM stdin;
DISP01	TRK01	RT01	DRV01	AST01	2026-08-01 08:00:00	2026-08-01 13:00:00
DISP02	TRK02	RT02	DRV02	AST02	2026-08-04 08:00:00	2026-08-04 13:00:00
DISP03	TRK03	RT03	DRV03	AST03	2026-08-07 08:00:00	2026-08-07 13:00:00
DISP04	TRK04	RT04	DRV04	AST04	2026-08-10 08:00:00	2026-08-10 13:00:00
DISP05	TRK05	RT05	DRV05	AST05	2026-08-13 08:00:00	2026-08-13 13:00:00
DISP06	TRK06	RT06	DRV06	AST06	2026-08-16 08:00:00	2026-08-16 13:00:00
DISP07	TRK07	RT07	DRV07	AST07	2026-08-19 08:00:00	2026-08-19 13:00:00
DISP08	TRK08	RT08	DRV08	AST08	2026-08-22 08:00:00	2026-08-22 13:00:00
DISP09	TRK01	RT09	DRV01	AST01	2026-08-25 08:00:00	2026-08-25 13:00:00
DISP10	TRK02	RT10	DRV02	AST02	2026-08-28 08:00:00	2026-08-28 13:00:00
DISP11	TRK03	RT01	DRV03	AST03	2026-08-31 08:00:00	2026-08-31 13:00:00
DISP12	TRK04	RT02	DRV04	AST04	2026-09-03 08:00:00	2026-09-03 13:00:00
DISP13	TRK05	RT03	DRV05	AST05	2026-09-06 08:00:00	2026-09-06 13:00:00
DISP14	TRK06	RT04	DRV06	AST06	2026-09-09 08:00:00	2026-09-09 13:00:00
DISP15	TRK07	RT05	DRV07	AST07	2026-09-12 08:00:00	2026-09-12 13:00:00
\.


--
-- Name: assistant assistant_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant
    ADD CONSTRAINT assistant_pkey PRIMARY KEY (assistant_id);


--
-- Name: city city_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.city
    ADD CONSTRAINT city_pkey PRIMARY KEY (city_id);


--
-- Name: customer_order customer_order_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order
    ADD CONSTRAINT customer_order_pkey PRIMARY KEY (order_id);


--
-- Name: customer customer_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_pkey PRIMARY KEY (customer_id);


--
-- Name: driver driver_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.driver
    ADD CONSTRAINT driver_pkey PRIMARY KEY (driver_id);


--
-- Name: order_item order_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item
    ADD CONSTRAINT order_item_pkey PRIMARY KEY (order_id, product_id);


--
-- Name: order_travel order_travel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_travel
    ADD CONSTRAINT order_travel_pkey PRIMARY KEY (order_id, trip_id);


--
-- Name: order_trip_item order_trip_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_trip_item
    ADD CONSTRAINT order_trip_item_pkey PRIMARY KEY (order_id, trip_id, product_id);


--
-- Name: product product_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (product_id);


--
-- Name: route route_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route
    ADD CONSTRAINT route_pkey PRIMARY KEY (route_id);


--
-- Name: staff_user staff_user_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_user
    ADD CONSTRAINT staff_user_email_key UNIQUE (email);


--
-- Name: staff_user staff_user_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_user
    ADD CONSTRAINT staff_user_pkey PRIMARY KEY (staff_id);


--
-- Name: store store_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store
    ADD CONSTRAINT store_pkey PRIMARY KEY (store_id);


--
-- Name: train train_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.train
    ADD CONSTRAINT train_pkey PRIMARY KEY (train_id);


--
-- Name: train_schedule train_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.train_schedule
    ADD CONSTRAINT train_schedule_pkey PRIMARY KEY (trip_id);


--
-- Name: truck_dispatch truck_dispatch_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.truck_dispatch
    ADD CONSTRAINT truck_dispatch_pkey PRIMARY KEY (dispatch_id);


--
-- Name: truck truck_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.truck
    ADD CONSTRAINT truck_pkey PRIMARY KEY (truck_id);


--
-- Name: customer uq_customer_email; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT uq_customer_email UNIQUE (email);


--
-- Name: idx_customer_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_city ON public.customer USING btree (city_id);


--
-- Name: idx_customer_order_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_order_customer ON public.customer_order USING btree (customer_id);


--
-- Name: idx_customer_order_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_order_dates ON public.customer_order USING btree (placement_date, delivery_date);


--
-- Name: idx_dispatch_assistant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dispatch_assistant ON public.truck_dispatch USING btree (assistant_id);


--
-- Name: idx_dispatch_driver; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dispatch_driver ON public.truck_dispatch USING btree (driver_id);


--
-- Name: idx_dispatch_start_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dispatch_start_time ON public.truck_dispatch USING btree (start_time);


--
-- Name: idx_dispatch_truck; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dispatch_truck ON public.truck_dispatch USING btree (truck_id);


--
-- Name: idx_order_item_product; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_item_product ON public.order_item USING btree (product_id);


--
-- Name: idx_order_travel_route; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_travel_route ON public.order_travel USING btree (route_id);


--
-- Name: idx_order_travel_trip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_travel_trip ON public.order_travel USING btree (trip_id);


--
-- Name: idx_order_trip_item_trip; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_trip_item_trip ON public.order_trip_item USING btree (trip_id);


--
-- Name: idx_route_store; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_route_store ON public.route USING btree (store_id);


--
-- Name: idx_store_city; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_store_city ON public.store USING btree (city_id);


--
-- Name: idx_train_schedule_store_departure; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_train_schedule_store_departure ON public.train_schedule USING btree (store_id, departure_datetime, trip_id);


--
-- Name: order_item kp_booked_item_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kp_booked_item_guard BEFORE INSERT OR DELETE OR UPDATE ON public.order_item FOR EACH ROW EXECUTE FUNCTION public.kp_booked_item_guard();


--
-- Name: order_travel kp_booked_travel_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kp_booked_travel_guard BEFORE DELETE OR UPDATE ON public.order_travel FOR EACH ROW EXECUTE FUNCTION public.kp_booked_travel_guard();


--
-- Name: customer_order kp_cancel_reservations; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kp_cancel_reservations AFTER UPDATE OF status ON public.customer_order FOR EACH ROW EXECUTE FUNCTION public.kp_cancel_reservations();


--
-- Name: train_schedule kp_new_trip_capacity; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kp_new_trip_capacity BEFORE INSERT ON public.train_schedule FOR EACH ROW EXECUTE FUNCTION public.kp_new_trip_capacity();


--
-- Name: customer_order kp_order_status_guard; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kp_order_status_guard BEFORE UPDATE OF status ON public.customer_order FOR EACH ROW EXECUTE FUNCTION public.kp_order_status_guard();


--
-- Name: order_trip_item kp_reserve_train_space; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kp_reserve_train_space BEFORE INSERT OR DELETE OR UPDATE ON public.order_trip_item FOR EACH ROW EXECUTE FUNCTION public.kp_reserve_train_space();


--
-- Name: truck_dispatch trg_assistant_max_consecutive; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_assistant_max_consecutive BEFORE INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_assistant_max_consecutive();


--
-- Name: truck_dispatch trg_assistant_no_overlap; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_assistant_no_overlap BEFORE INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_assistant_no_overlap();


--
-- Name: truck_dispatch trg_assistant_weekly_hours; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_assistant_weekly_hours BEFORE INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_assistant_weekly_hours();


--
-- Name: truck_dispatch trg_driver_no_consecutive; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_driver_no_consecutive BEFORE INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_driver_no_consecutive();


--
-- Name: truck_dispatch trg_driver_no_overlap; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_driver_no_overlap BEFORE INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_driver_no_overlap();


--
-- Name: truck_dispatch trg_driver_weekly_hours; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_driver_weekly_hours BEFORE INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_driver_weekly_hours();


--
-- Name: truck_dispatch trg_truck_no_overlap; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_truck_no_overlap BEFORE INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_truck_no_overlap();


--
-- Name: truck_dispatch trg_update_driver_hours; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_driver_hours AFTER INSERT ON public.truck_dispatch FOR EACH ROW EXECUTE FUNCTION public.trg_fn_update_hours();


--
-- Name: customer customer_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer
    ADD CONSTRAINT customer_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.city(city_id);


--
-- Name: customer_order customer_order_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_order
    ADD CONSTRAINT customer_order_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customer(customer_id);


--
-- Name: order_item order_item_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item
    ADD CONSTRAINT order_item_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.customer_order(order_id);


--
-- Name: order_item order_item_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_item
    ADD CONSTRAINT order_item_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.product(product_id);


--
-- Name: order_travel order_travel_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_travel
    ADD CONSTRAINT order_travel_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.customer_order(order_id);


--
-- Name: order_travel order_travel_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_travel
    ADD CONSTRAINT order_travel_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.route(route_id);


--
-- Name: order_travel order_travel_trip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_travel
    ADD CONSTRAINT order_travel_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES public.train_schedule(trip_id);


--
-- Name: order_trip_item order_trip_item_order_id_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_trip_item
    ADD CONSTRAINT order_trip_item_order_id_product_id_fkey FOREIGN KEY (order_id, product_id) REFERENCES public.order_item(order_id, product_id);


--
-- Name: order_trip_item order_trip_item_order_id_trip_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_trip_item
    ADD CONSTRAINT order_trip_item_order_id_trip_id_fkey FOREIGN KEY (order_id, trip_id) REFERENCES public.order_travel(order_id, trip_id);


--
-- Name: route route_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route
    ADD CONSTRAINT route_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.store(store_id);


--
-- Name: store store_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store
    ADD CONSTRAINT store_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.city(city_id);


--
-- Name: train_schedule train_schedule_city_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.train_schedule
    ADD CONSTRAINT train_schedule_city_id_fkey FOREIGN KEY (city_id) REFERENCES public.city(city_id);


--
-- Name: train_schedule train_schedule_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.train_schedule
    ADD CONSTRAINT train_schedule_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.store(store_id);


--
-- Name: train_schedule train_schedule_train_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.train_schedule
    ADD CONSTRAINT train_schedule_train_id_fkey FOREIGN KEY (train_id) REFERENCES public.train(train_id);


--
-- Name: truck_dispatch truck_dispatch_assistant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.truck_dispatch
    ADD CONSTRAINT truck_dispatch_assistant_id_fkey FOREIGN KEY (assistant_id) REFERENCES public.assistant(assistant_id);


--
-- Name: truck_dispatch truck_dispatch_driver_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.truck_dispatch
    ADD CONSTRAINT truck_dispatch_driver_id_fkey FOREIGN KEY (driver_id) REFERENCES public.driver(driver_id);


--
-- Name: truck_dispatch truck_dispatch_route_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.truck_dispatch
    ADD CONSTRAINT truck_dispatch_route_id_fkey FOREIGN KEY (route_id) REFERENCES public.route(route_id);


--
-- Name: truck_dispatch truck_dispatch_truck_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.truck_dispatch
    ADD CONSTRAINT truck_dispatch_truck_id_fkey FOREIGN KEY (truck_id) REFERENCES public.truck(truck_id);


--
-- Name: truck truck_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.truck
    ADD CONSTRAINT truck_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.store(store_id);


--
-- PostgreSQL database dump complete
--

\unrestrict 9SR7bGBK8DIud4XFSPXAJBU1CVfB8yiMwPbgnrJMjezs4Q60yaQDhjyY24gaohN

