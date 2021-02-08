#!/usr/bin/env python3

import json, random, string, websocket, http.client, sys, time, lorem

rooms = [str(i) for i in range(5)]
users = [''.join(random.choices(string.ascii_letters + string.digits, k=8)) for i in range(10)]

sockets = {room: {} for room in rooms}

host = 'localhost:8000' if len(sys.argv) < 2 else sys.argv[1]

def join(room, user):
    print("Joining", room, "with", user)
    ws = websocket.create_connection("ws://{}/websocket".format(host))
    ws.send("join:{room}:{user}:{user}".format(room=room, user=user))
    sockets[room][user] = ws

def leave(room, user):
    print("Quitting", room, "with", user)
    sockets[room][user].close()
    del sockets[room][user]

def get_state(room, user):
    print("Getting state for", room, "with", user)
    status = -1
    while status != 200:
        connection = http.client.HTTPConnection(host)
        connection.request('GET', "/state.json?room={room}&id={user}".format(room=room, user=user))
        response = connection.getresponse()
        status = response.status
    content = response.read()
    return json.loads(content)

def set_config(room, ai, random, partners, openhands, aitime):
    print("Setting config for", room, ":", "ai={}&random={}&partners={}&openhands={}&aitime={}".format(ai, random, partners, openhands, aitime))
    connection = http.client.HTTPConnection(host)
    connection.request('GET', "/config?room={room}&ai={}&random={}&partners={}&openhands={}&aitime={}".format(ai, random, partners, openhands, aitime, room=room))

def start(room):
    print("Starting", room)
    connection = http.client.HTTPConnection(host)
    connection.request('GET', '/start?room=' + room)

def end(room):
    print("Ending")
    connection = http.client.HTTPConnection(host)
    connection.request('GET', '/end?room=' + room)

def chat(room, user):
    print("Chat in", room, "for", user)
    sockets[room][user].send("chat:" + lorem.sentence())

def label(room, user):
    label = str(random.randint(0, 100))
    print("Label in", room, "for", user, ":", label)
    sockets[room][user].send("label:" + label)

def action(room, user, i):
    print("Action", i, "in", room, "for", user)
    sockets[room][user].send("action:" + str(i))

def test():
    while True:
        #time.sleep(1)
        room = random.choice(rooms)
        if len(sockets[room]) == 0:
            join(room, random.choice(users))
        user = random.choice(list(sockets[room].keys()))
        state = get_state(room, user)
        actions = [
            lambda: set_config(room, state['aiPlayers'] + 1, state['randomPlayers'], state['partners'], state['openHands'], state['aiTime']),
            lambda: set_config(room, state['aiPlayers'] - 1, state['randomPlayers'], state['partners'], state['openHands'], state['aiTime']),
            lambda: set_config(room, state['aiPlayers'], state['randomPlayers'] + 1, state['partners'], state['openHands'], state['aiTime']),
            lambda: set_config(room, state['aiPlayers'], state['randomPlayers'] - 1, state['partners'], state['openHands'], state['aiTime']),
            lambda: set_config(room, state['aiPlayers'], state['randomPlayers'], not state['partners'], state['openHands'], state['aiTime']),
            lambda: set_config(room, state['aiPlayers'], state['randomPlayers'], state['partners'], not state['openHands'], state['aiTime']),
            lambda: set_config(room, state['aiPlayers'], state['randomPlayers'], state['partners'], state['openHands'], state['aiTime'] + 1),
            lambda: set_config(room, state['aiPlayers'], state['randomPlayers'], state['partners'], state['openHands'], state['aiTime'] - 1),
            lambda: chat(room, user),
            lambda: label(room, user),
            lambda: join(room, user),
            lambda: leave(room, user)
        ]
        if 'turn' in state:
            actions.append(lambda: end(room))
            print(state['playersInGame'], state['turn'])
            turnUser = state['playersInGame'][state['turn']]
            if turnUser.startswith('AI') or turnUser.startswith('Random'):
                # Waiting on an AI: try another room
                continue
            elif turnUser not in users:
                # Game has a player that is not included by the test script, possibly from a previous run: end the game
                end(room)
                continue
            elif turnUser not in sockets[room]:
                # User isn't currently in the room: rejoin
                join(room, turnUser)
            turnUserState = get_state(room, turnUser)
            moves = [lambda: action(room, turnUser, i) for i in range(0, len(turnUserState['actions']))]
            actions.extend(moves * 10)  # Higher probability of making a move
        else:
            actions.append(lambda: start(room))
        random.choice(actions)()

if __name__ == '__main__':
    print("Testing on", host)
    test()
