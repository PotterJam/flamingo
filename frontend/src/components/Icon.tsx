import React from 'react';

import clayStopwatch from '../assets/icons/clay-stopwatch.png';
import clayArrowWhite from '../assets/icons/clay-arrow-white.png';
import clayArrowBlack from '../assets/icons/clay-arrow-black.png';
import clayArrowPink from '../assets/icons/clay-arrow-pink.png';
import clayChat from '../assets/icons/clay-chat.png';
import clayHourglass from '../assets/icons/clay-hourglass.png';
import clayTick from '../assets/icons/clay-tick.png';
import clayCross from '../assets/icons/clay-cross.png';
import clayPaintPink from '../assets/icons/clay-paint-pink.png';
import clayPaintBlue from '../assets/icons/clay-paint-blue.png';
import clayRubber from '../assets/icons/clay-rubber.png';
import clayPencil from '../assets/icons/clay-pencil.png';
import clayAvatar from '../assets/icons/clay-avatar.png';
import clayPersonSilhouette from '../assets/icons/clay-person-silhouette.png';
import clayCog from '../assets/icons/clay-cog.png';
import clayStar from '../assets/icons/clay-star.png';

export type IconName =
    | 'clay-stopwatch'
    | 'clay-arrow-white'
    | 'clay-arrow-black'
    | 'clay-arrow-pink'
    | 'clay-chat'
    | 'clay-hourglass'
    | 'clay-tick'
    | 'clay-cross'
    | 'clay-paint-pink'
    | 'clay-paint-blue'
    | 'clay-rubber'
    | 'clay-pencil'
    | 'clay-avatar'
    | 'clay-person-silhouette'
    | 'clay-cog'
    | 'clay-star';

const iconMap: Record<IconName, string> = {
    'clay-stopwatch': clayStopwatch,
    'clay-arrow-white': clayArrowWhite,
    'clay-arrow-black': clayArrowBlack,
    'clay-arrow-pink': clayArrowPink,
    'clay-chat': clayChat,
    'clay-hourglass': clayHourglass,
    'clay-tick': clayTick,
    'clay-cross': clayCross,
    'clay-paint-pink': clayPaintPink,
    'clay-paint-blue': clayPaintBlue,
    'clay-rubber': clayRubber,
    'clay-pencil': clayPencil,
    'clay-avatar': clayAvatar,
    'clay-person-silhouette': clayPersonSilhouette,
    'clay-cog': clayCog,
    'clay-star': clayStar,
};

export type IconSize = 'xs' | 's' | 'm' | 'l';

const sizeMap: Record<IconSize, number> = {
    xs: 16,
    s: 32,
    m: 48,
    l: 64,
};

export interface IconProps {
    name: IconName;
    size?: IconSize;
    alt?: string;
    className?: string;
}

export const Icon: React.FC<IconProps> = ({
    name,
    size = 'm',
    alt,
    className = '',
}) => {
    const iconSrc = iconMap[name];

    return (
        <img
            src={iconSrc}
            alt={alt || name}
            width={sizeMap[size]}
            height={sizeMap[size]}
            className={`icon ${className}`}
            style={{
                display: 'inline-block',
                verticalAlign: 'middle',
            }}
        />
    );
};
