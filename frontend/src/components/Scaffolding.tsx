import { FC, PropsWithChildren } from 'react';
import { FlamingoBackground } from './Background';

export const Scaffolding: FC<PropsWithChildren<{}>> = ({ children }) => {
    return (
        <>
            <FlamingoBackground />
            <main className="flex min-h-screen flex-col items-center justify-start bg-gray-100 p-4 font-sans">
                <h1 className="font-lilita mb-4 flex-shrink-0 text-3xl font-bold text-pink-400">
                    Flamin<span className="text-sky-400">go</span>
                </h1>
                {children}
            </main>
        </>
    );
};
