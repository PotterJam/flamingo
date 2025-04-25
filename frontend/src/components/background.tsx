import React, { FC } from 'react';

export const FlamingoBackground: FC = () => {
    const numRows = 30;
    const numCols = 40;
    const rowHeightRem = 3;
    const colWidthRem = 9.5;

    const rows = [];

    for (let i = 0; i < numRows; i++) {
        const isOffsetRow = i % 2 !== 0;
        const columns = [];
        for (let j = 0; j < numCols; j++) {
            const style: React.CSSProperties = {
                top: `${i * rowHeightRem}rem`,
                left: `${j * colWidthRem - (isOffsetRow ? colWidthRem / 2 : 0)}rem`,
                position: 'absolute',
            };

            columns.push(
                <span
                    key={`${i}-${j}`}
                    className={`font-lilita text-4xl font-extrabold whitespace-nowrap text-pink-300 opacity-30 select-none`}
                    style={style}
                    aria-hidden="true"
                >
                    flamingo
                </span>
            );
        }
        rows.push(...columns);
    }

    return (
        <div className={`fixed inset-0 -z-10 overflow-hidden bg-pink-200`}>
            <div className="relative h-full w-full">{rows}</div>
        </div>
    );
};
