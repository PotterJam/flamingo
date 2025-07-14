import { createSignal } from 'solid-js';
import { actions } from '../store';
import { CreateRoomResponse } from '../api';
import { Logo } from './Logo';
import { soundManager } from '../sound-manager';
import { Card, CardContent, CardHeader } from './ui/card';
import { Button } from './ui/button';
import { Separator } from './ui/separator';
import { GridBackground } from './GridBackground';

export const RoomConnection = () => {
    const [name, setName] = createSignal('');
    const [roomName, setRoomName] = createSignal('');
    const [roomNotFound, setRoomNotFound] = createSignal(false);

    const createRoom = async () => {
        const response = await fetch('/create-room', {
            method: 'POST',
            headers: { Accept: 'application/json' },
        });
        const room: CreateRoomResponse = await response.json();

        soundManager.playSound('join');
        actions.nameChosen(name());
        actions.roomCreated(room.roomId);
    };

    const findRoom = async () => {
        const response = await fetch(`/${roomName()}`, {
            method: 'GET',
        });

        if (response.status == 200) {
            actions.nameChosen(name());
            setRoomNotFound(false);
            soundManager.playSound('join');
            actions.joinRoom(roomName());
        }

        if (response.status == 404) {
            console.log('room not found');
            setRoomNotFound(true);
        }
    };

    return (
        <GridBackground>
            <div class="flex h-full w-full flex-col items-center justify-center">
                <Card class="mx-auto w-full max-w-sm p-6 text-center">
                    <CardHeader>
                        <Logo />
                    </CardHeader>
                    <CardContent class="flex flex-col gap-6">
                        <input
                            type="text"
                            value={name()}
                            onInput={(e) => setName(e.target.value)}
                            placeholder="Enter your name"
                            maxLength={20}
                            required
                            class="rounded-base border-border placeholder:text-muted-foreground mt-1 flex h-10 w-full border-2 bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-black focus:ring-offset-2 focus:outline-none"
                            aria-label="Enter your name"
                        />
                        <Separator />
                        <div>
                            {roomNotFound() && (
                                <p class="text-red-400">
                                    That room doesn't exist
                                </p>
                            )}
                            <div class="flex flex-row gap-1">
                                <input
                                    type="text"
                                    placeholder="Room name"
                                    value={roomName()}
                                    onInput={(e) => {
                                        setRoomName(e.target.value);
                                        setRoomNotFound(false);
                                    }}
                                    aria-label="Enter room name to join"
                                    class="rounded-base border-border bg-background placeholder:text-muted-foreground mt-1 flex h-10 w-full border-2 bg-white px-3 py-2 text-sm focus:ring-2 focus:ring-black focus:ring-offset-2 focus:outline-none"
                                />
                                <Button
                                    disabled={
                                        !(roomName().trim() && name().trim())
                                    }
                                    variant="outline"
                                    class="mt-1 ml-1"
                                    onClick={findRoom}
                                >
                                    Join
                                </Button>
                            </div>
                            <h3 class="p-2 text-gray-500 italic">or</h3>
                            <Button
                                variant="default"
                                disabled={!name().trim() || !!roomName().trim()}
                                onClick={createRoom}
                                class="w-full"
                            >
                                Create room
                            </Button>
                        </div>
                    </CardContent>
                </Card>
            </div>
        </GridBackground>
    );
};
