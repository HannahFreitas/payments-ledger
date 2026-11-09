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
-- Name: entries_append_only(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.entries_append_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'entries are append-only' USING ERRCODE = 'insufficient_privilege';
END;
$$;


--
-- Name: entries_balanced(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.entries_balanced() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  total bigint;
BEGIN
  SELECT COALESCE(SUM(amount_cents), 0) INTO total FROM entries WHERE transfer_id = NEW.transfer_id;
  IF total <> 0 THEN
    RAISE EXCEPTION 'transfer % is unbalanced: entries sum to %', NEW.transfer_id, total
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accounts (
    id bigint NOT NULL,
    name character varying NOT NULL,
    currency character varying(3) NOT NULL,
    kind character varying DEFAULT 'customer'::character varying NOT NULL,
    balance_cents bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT accounts_currency_iso4217 CHECK (((currency)::text ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT accounts_customer_not_negative CHECK ((((kind)::text = 'system'::text) OR (balance_cents >= 0))),
    CONSTRAINT accounts_kind_known CHECK (((kind)::text = ANY (ARRAY[('customer'::character varying)::text, ('system'::character varying)::text])))
);


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.accounts_id_seq OWNED BY public.accounts.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entries (
    id bigint NOT NULL,
    transfer_id bigint NOT NULL,
    account_id bigint NOT NULL,
    amount_cents bigint NOT NULL,
    balance_after_cents bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT entries_amount_not_zero CHECK ((amount_cents <> 0))
);


--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entries_id_seq OWNED BY public.entries.id;


--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_keys (
    id bigint NOT NULL,
    key character varying NOT NULL,
    request_fingerprint character varying NOT NULL,
    response_status integer NOT NULL,
    response_body jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT idempotency_keys_key_length CHECK (((char_length((key)::text) >= 1) AND (char_length((key)::text) <= 255)))
);


--
-- Name: idempotency_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idempotency_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: idempotency_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.idempotency_keys_id_seq OWNED BY public.idempotency_keys.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transfers (
    id bigint NOT NULL,
    from_account_id bigint NOT NULL,
    to_account_id bigint NOT NULL,
    amount_cents bigint NOT NULL,
    currency character varying(3) NOT NULL,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT transfers_amount_positive CHECK ((amount_cents > 0)),
    CONSTRAINT transfers_distinct_accounts CHECK ((from_account_id <> to_account_id))
);


--
-- Name: transfers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transfers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transfers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transfers_id_seq OWNED BY public.transfers.id;


--
-- Name: accounts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts ALTER COLUMN id SET DEFAULT nextval('public.accounts_id_seq'::regclass);


--
-- Name: entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries ALTER COLUMN id SET DEFAULT nextval('public.entries_id_seq'::regclass);


--
-- Name: idempotency_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys ALTER COLUMN id SET DEFAULT nextval('public.idempotency_keys_id_seq'::regclass);


--
-- Name: transfers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers ALTER COLUMN id SET DEFAULT nextval('public.transfers_id_seq'::regclass);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: entries entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: transfers transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT transfers_pkey PRIMARY KEY (id);


--
-- Name: index_entries_on_account_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_account_id_and_id ON public.entries USING btree (account_id, id DESC);


--
-- Name: index_entries_on_transfer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_transfer_id ON public.entries USING btree (transfer_id);


--
-- Name: index_idempotency_keys_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_idempotency_keys_on_key ON public.idempotency_keys USING btree (key);


--
-- Name: index_transfers_on_from_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_from_account_id ON public.transfers USING btree (from_account_id);


--
-- Name: index_transfers_on_to_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transfers_on_to_account_id ON public.transfers USING btree (to_account_id);


--
-- Name: entries entries_must_balance; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER entries_must_balance AFTER INSERT OR UPDATE ON public.entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.entries_balanced();


--
-- Name: entries entries_no_update_or_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER entries_no_update_or_delete BEFORE DELETE OR UPDATE ON public.entries FOR EACH ROW EXECUTE FUNCTION public.entries_append_only();


--
-- Name: transfers fk_rails_0ed16a9709; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_0ed16a9709 FOREIGN KEY (to_account_id) REFERENCES public.accounts(id);


--
-- Name: entries fk_rails_37a3feaeb6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_37a3feaeb6 FOREIGN KEY (account_id) REFERENCES public.accounts(id);


--
-- Name: transfers fk_rails_3b260aee3c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transfers
    ADD CONSTRAINT fk_rails_3b260aee3c FOREIGN KEY (from_account_id) REFERENCES public.accounts(id);


--
-- Name: entries fk_rails_c31140256b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT fk_rails_c31140256b FOREIGN KEY (transfer_id) REFERENCES public.transfers(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261109190200'),
('20261109190100'),
('20261109190000');

