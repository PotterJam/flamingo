import { ParentComponent } from 'solid-js';

export const GridBackground: ParentComponent = (props) => {
    return <div class="grid-background h-full w-full">{props.children}</div>;
};
