#!/usr/local/bin/python3
#
# Search for Bear Notes with Launchbar
#
# Author: Teemu Turpeinen, 2021
#
import sqlite3
import sys
import json
import os
import re

HOME = os.getenv('HOME', '')
bear_base: str = os.path.join(HOME, 'Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data')
bear_db: str = os.path.join(bear_base, 'database.sqlite')
search_str: list = []


def clear_filter(filter_str: str, suffix: str) -> str:
    filter_str = filter_str.strip()

    if filter_str.endswith(suffix):
        filter_str = filter_str[:-(len(suffix))]

    return filter_str


def construct_query(query_opt: list) -> dict:
    global search_str
    in_limit: bool = False
    title_limit: str = ""
    text_limit: str = ""
    query: dict = {}
    keywords: list = ['AND', 'OR']
    query_filter: str = "OR"

    if query_opt[0] in keywords:
        query_filter = query_opt.pop(0)

    for i in query_opt:
        if i in keywords:
            if in_limit:
                title_limit = clear_filter(title_limit, query_filter) + ") "
                text_limit = clear_filter(text_limit, query_filter) + ") "

            title_limit = clear_filter(title_limit, query_filter) + i + " ("
            text_limit = clear_filter(text_limit, query_filter) + i + " ("

            in_limit = True
        elif i != "":
            search_str.append(i)
            if in_limit:
                title_limit += "ZTITLE like \'%" + i + "%\' " + query_filter + " "
                text_limit += "ZTEXT like \'%" + i + "%\' " + query_filter + " "
            else:
                title_limit += "(ZTITLE like \'%" + i + "%\') " + query_filter + " "
                text_limit += "(ZTEXT like \'%" + i + "%\') " + query_filter + " "

    title_limit = clear_filter(title_limit, query_filter)
    text_limit = clear_filter(text_limit, query_filter)

    if in_limit:
        title_limit += ")"
        text_limit += ")"

    query['text'] = text_limit
    query['title'] = title_limit

    return query


def get_sub_title(criteria: list, note_text: str) -> str:
    sub_title: str = ""
    suffix: str = " ... "
    
    for s in criteria:
        if s == "":
            continue

        check_str = re.search(r'%s' % s, note_text, re.IGNORECASE)

        if check_str is None:
            continue

        beg: int = check_str.span()[0] - 12
        end: int = check_str.span()[1] + 12

        txt: str = note_text[beg: end]
        while not re.match(r"^\W", txt, re.IGNORECASE) and not note_text.startswith(s) and beg > 0:
            beg -= 1
            txt = note_text[beg: end]

        while not re.search(r"\W$", txt, re.IGNORECASE) and not note_text.endswith(s) and end < len(
                note_text):
            end += 1
            txt = note_text[beg: end]

        sub_title += txt + suffix

    if len(sub_title) >= len(suffix):
        sub_title = sub_title[:-len(suffix)]

    return sub_title


def search():
    query: str = " ".join(sys.argv[1:]).strip()
    notes: list = []

    if query is not None and query != "":
        query = query.strip()

        if len(query) < 3:
            return

        query_base: str = "SELECT ZTITLE, ZUNIQUEIDENTIFIER, ZTEXT FROM ZSFNOTE " \
                          "WHERE ZTRASHED = 0 AND ZARCHIVED = 0 AND ZENCRYPTED = 0"

        if query.endswith("AND") or query.endswith("OR"):
            query = clear_filter(query, "AND")
            query = clear_filter(query, "OR")

        query_opt: list = query.split(" ")
        q: dict = construct_query(query_opt)
        query = query_base + " AND ((" + str(q['title']).strip() + ") OR (" + str(q['text']).strip() + "))"

        with sqlite3.connect(bear_db) as conn:
            conn.row_factory = sqlite3.Row
            c = conn.execute(query)

        for row in c:
            note_text: str = row['ZTEXT'].replace("\n", ' ')
            sub_title: str = get_sub_title(search_str, note_text)

            note: dict = {'icon': 'Bear-Icon.png', 'title': row['ZTITLE'], 'subtitle': sub_title,
                          'alwaysShowsSubtitle': 'true',
                          'url': 'bear://x-callback-url/open-note?new_window=yes&id=' + row['ZUNIQUEIDENTIFIER']}
            notes.append(note)

    print(json.dumps(notes))


search()
