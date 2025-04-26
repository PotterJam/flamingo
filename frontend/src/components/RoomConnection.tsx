import { FC } from 'react';
import { PrimaryButton } from './buttons/PrimaryButton';
import { useAppStore } from '../store';
import { CreateRoomResponse } from '../api';

export const RoomConnection: FC = () => {
    const roomCreated = useAppStore((s) => s.roomCreated);

    const createRoom = async () => {
        const response = await fetch('/create-room', {
            method: 'POST',
            headers: { Accept: 'application/json' },
        });
        const room: CreateRoomResponse = await response.json();

        roomCreated(room);
    };

    return (
        <div>
            <PrimaryButton onClick={createRoom}>Create room</PrimaryButton>
        </div>
    );
};
